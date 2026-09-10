# TrueArena — Architecture Reference (v1 / Track A)

> Scope: Track A (native app + backend). Track B (web + host display) and Section 11
> (retention/vision) are roadmap — seams are noted where cheap, nothing more.
> Companion to the Build Brief. Where the brief states a rationale, it wins unless
> there is a concrete technical reason — flag and ask, don't silently change.

---

## 1. System topology

```
┌─────────────┐         ┌──────────────────────────────────────────────┐
│ Flutter app │◄───────►│  API Gateway / LB (nginx or cloud LB, TLS)   │
│  (iOS/And)  │  HTTPS   └───────────────┬──────────────────────────────┘
└──────┬──────┘  WSS                     │
       │                    ┌────────────┴─────────────┐
       │ LiveKit WebRTC     │   truearena-backend      │  Spring Boot 3 / WebFlux
       │                    │   (stateless, N pods)    │  - REST: auth, groups, rooms
       │                    │                          │  - WS:  /ws/room/{id}
       ▼                    │   ┌──────────────────┐   │  - game engine (in-process)
┌─────────────┐             │   │ GameEngine core  │   │
│  LiveKit    │             │   │ + TrueArena mod  │   │
│  SFU (self- │             │   └──────────────────┘   │
│  hosted)    │             └───┬───────────┬──────────┘
└──────┬──────┘                 │           │
       │ webhooks                │           │
       ▼                         ▼           ▼
┌─────────────┐          ┌─────────────┐  ┌──────────────┐
│  backend    │◄────────►│   Redis     │  │  Postgres 16 │
│  (webhook   │          │  (sentinel/ │  │  (primary +  │
│   handler)  │          │   cluster)  │  │   replica)   │
└─────────────┘          └─────────────┘  └──────────────┘
```

Backend pods are **stateless**. All live room state lives in Redis so any pod can
serve any socket, and pods can restart/scale without killing games.

---

## 2. Components

### 2.1 `truearena-backend` (Java 21, Spring Boot 3.3, WebFlux)

| Module | Responsibility |
|---|---|
| `ta-app` | Spring Boot entrypoint, wiring, config profiles. |
| `ta-api` | REST: OTP auth, users, friends, groups, room creation/join. Reactive, R2DBC. |
| `ta-ws` | Reactive WebSocket handler `/ws/room/{roomId}`. Subscribe/publish loop, per-subscriber state filtering, event-log replay. |
| `ta-engine` | Transport-agnostic engine. `GameModule` interface, phase/timer state machine, `GameState` reducer, event-log writer. **No Spring, no I/O** — pure functions + a scheduler port. |
| `ta-game-truearena` | The one `GameModule` impl — the *Traitors and Faithful* social-deduction engine. Config-driven: phase set (incl. **MorningReveal**), night-kill cadence, reveal policy, **Veiled Endgame**, tie/AFK presets, and a `TwistRegistry` of enumerated twists. Modes are data, not code. Full model: [GAME_CONFIG.md](GAME_CONFIG.md). |
| `ta-room` | Room lifecycle: Redis-backed registry, membership, ready-check, host migration, reconnection tokens. |
| `ta-voice` | LiveKit admin: mints tokens, force-mutes on Vote phase entry, consumes LiveKit webhooks. |
| `ta-persistence` | R2DBC repos, Flyway migrations, write-behind flush of `GameEvent`/`GameResult`/`PlayerStat` to Postgres at session end. |
| `ta-contract-tests` | Full-session integration + the secret-data guarantee test. Also runnable as a headless bot client. |

**Why the engine is Spring-free:** it is the Section 8 non-negotiable and the piece
Track B and Section 11 mods reuse. Framework-free = trivially unit-testable (feed
actions, assert state + per-player visible projections) and impossible to couple to
transport by accident.

### 2.2 Redis — ephemeral authority for live games

| Key | Type | Purpose | TTL |
|---|---|---|---|
| `room:{id}:meta` | Hash | status, hostId, groupId, config | 6h sliding |
| `room:{id}:members` | Hash (userId → json) | connection_status, ready_state | 6h |
| `room:{id}:state` | String (JSON) | current `GameState` snapshot | 6h |
| `room:{id}:events` | Stream | append-only `GameEvent` log; `seq` = stream id | 6h |
| `room:{id}:phase` | String + `PEXPIRE` | phase name; key-expiry drives timer advance | phase length |
| `room:{id}:channel` | Pub/Sub | fan-out of new events to all pods holding sockets for this room | — |
| `session:{token}` | String | userId + roomId, for reconnect | 12h |
| `lock:room:{id}` | String (`SET NX PX`) | serialize state mutations for one room | 5s |

**Timer mechanism:** on entering a phase, `SET room:{id}:phase <name> PX <ms>`.
Subscribe to keyspace notifications (`Ex`); on expiry, the pod that catches it grabs
`lock:room:{id}` and asks the engine for the transition. Belt-and-braces: a 2s
scheduled sweep reconciles missed expiries so a dropped notification can't stall a
game.

**State mutation flow (single-writer per room):**
1. Action arrives on any pod → `SET NX lock:room:{id}`.
2. Load `state` + config, call `engine.onPlayerAction(...)`.
3. `XADD` resulting events, `SET` new state, reset `phase` TTL if phase changed — pipelined.
4. `PUBLISH room:{id}:channel` with the new event seq range.
5. Release lock.

Every pod subscribed to that room's channel wakes, reads new events from the stream,
runs `getVisibleStateFor` **per local subscriber**, and pushes filtered frames down
each socket. Role data is never in the broadcast payload — filtering happens after
fan-out, per connection.

### 2.3 Postgres 16 — durable record

**Full column-level schema: [DATABASE.md](DATABASE.md)** (the migrations under
`ta-persistence/.../db/migration/` are the executable truth). Tables:

- `users`, `friends`, `groups`, `group_members` — accounts + social graph (V1).
- `rooms`, `room_members` — one live game instance, group-linked or ad-hoc (V2).
- `game_config_preset` — the 5 shipped modes (`scope='builtin'`, rewritten from code on
  every boot) + `group`/`user` custom games; a full `GameConfig` JSONB per row
  (see [GAME_CONFIG.md](GAME_CONFIG.md)).
- `game_sessions` (`config` JSONB + `config_preset_id` + `catalog_version` + `rng_seed`
  + `phase_ends_at`), `roles`, `game_events` (append-only, `visibility_scope`/`_key`),
  `votes`, `game_results` (V3).
- `player_stats` — one row per `(group_id, user_id)`; a `group_id IS NULL` row is the
  user's lifetime rollup (V4).

Rationale (brief §6): rooms aren't throwaway — Group history is the retention hook, so
at session end the event log + result belong to a durable Group. Live per-round state
(current votes, un-flushed events, in-play roles) is Redis-only during a game; the
tables are the record written at/near session end.

### 2.4 LiveKit (self-hosted SFU)

- One LiveKit `room` per TrueArena `Room`, same id.
- Backend is the only token issuer: `ta-voice` mints a join token when a player enters the lobby.
- **Vote phase enforcement:** engine emits `PHASE_CHANGED(vote)`; `ta-voice` calls LiveKit
  `UpdateParticipant`/`MutePublishedTrack` for every participant. Unmute on `Vote→VoteReview`.
  Discussion-phase host mute/unmute uses the same API for one target.
- LiveKit webhooks (`participant_joined`/`participant_left`) → backend → update
  `room:{id}:members` connection_status → feeds host-migration and AFK detection.
- Audio-only: clients publish mic only, request no video tracks.

---

## 3. Wire contracts

### 3.1 REST (`/api/v1`)

```
POST /auth/otp/request        { phone }                     → 204
POST /auth/otp/verify         { phone, code }               → { accessToken, refreshToken, user }
GET  /me                                                    → User
POST /groups                  { name }                      → Group
POST /groups/{id}/members     { userIdOrPhone }             → GroupMember
GET  /groups/{id}/stats                                     → per-group PlayerStat[]
POST /rooms                   { groupId? , config? }        → { room, joinCode, wsUrl, sessionToken }
POST /rooms/join              { joinCode, nickname? }       → { room, wsUrl, sessionToken }
GET  /rooms/{id}                                            → Room + members (no secret state)
```

Auth: JWT access token (15 min) + refresh token. Web-funnel joins (Track B) get a
scoped guest token tied to one room, no phone.

### 3.2 WebSocket — `/ws/room/{roomId}?session={sessionToken}`

Single envelope both directions:

```jsonc
{ "v": 1, "type": "STRING", "seq": 1234, "ts": 169..., "payload": { } }
```

**Client → server**

| type | payload |
|---|---|
| `HELLO` | `{ lastSeq }` — triggers replay-from-seq or full snapshot |
| `READY_SET` | `{ ready: bool }` |
| `CONFIG_SET` | `{ ...GameConfig }` (host only, lobby only) |
| `GAME_START` | `{}` (host only) |
| `PLAYER_ACTION` | `{ actionId, action: "NIGHT_TARGET" \| "CAST_VOTE" \| "REACT" \| ..., data }` |
| `HOST_CONTROL` | `{ cmd: "MUTE"\|"UNMUTE"\|"EXTEND_TIMER"\|"CUT_TIMER"\|"ADVANCE_PHASE"\|"REVEAL_NEXT"\|"RESOLVE_AFK"\|"BREAK_TIE", data }` |
| `PING` | `{}` |

**Server → client**

| type | payload |
|---|---|
| `SNAPSHOT` | full `PlayerVisibleState` (post-filter) |
| `EVENT` | one `GameEvent`, already filtered for this subscriber; may be redacted/dropped by `visibility_scope` |
| `PHASE` | `{ phase, endsAt }` |
| `ERROR` | `{ code, message }` |
| `PONG` | `{}` |

`seq` = Redis stream id, monotonic per room. Reconnect: client sends `HELLO {lastSeq}`;
if the stream still holds everything after `lastSeq`, server replays those `EVENT`s;
otherwise sends a fresh `SNAPSHOT`. Session token in the query string is validated
against `session:{token}` and rebinds the socket to the existing `RoomMember`.

### 3.3 Engine interface (brief §8, concrete signatures)

```java
public interface GameModule {
    String gameType();
    List<Phase> definePhases(GameConfig config);
    GameState initialState(List<PlayerId> players, GameConfig config, RandomSource rng);
    GameState onPlayerAction(GameState state, PlayerAction action);   // pure
    GameState onPhaseElapsed(GameState state, Phase ended);           // pure, timer-driven
    Optional<WinResult> checkWinCondition(GameState state);
    PlayerVisibleState getVisibleStateFor(GameState state, PlayerId player);
    PublicBroadcastState getBroadcastState(GameState state);          // Track B
    List<GameEvent> drainEvents(GameState prev, GameState next);      // for the log
}
```

`definePhases(config)` returns the per-round loop **`Lobby → RoleReveal → (Night →
MorningReveal → RoundTable → Vote → VoteReview → Elimination → WinCheck)* → FinalFire →
Results`**; `config.endgameVeil` makes `VoteReview`/`Elimination` run silent once living
players hit the threshold. Twist logic lives in a `TwistRegistry` the reducer consults
by id per phase — see [GAME_CONFIG.md](GAME_CONFIG.md).

`RandomSource` is seeded per session; the seed is stored on `GameSession` — makes
games replayable in tests and debuggable in prod.

---

## 4. Cross-cutting mechanisms

**Host migration:** `room:{id}:meta.hostId`. On host `participant_left` / WS close,
backend grabs the room lock, picks the longest-connected non-host member, updates
`hostId`, emits `HOST_CHANGED`. Mid-phase games keep running; only host-gated controls
transfer.

**AFK / vote grace:** at the Vote grace cutoff (config), engine emits
`AFK_PENDING {playerIds}`. Host resolves via `HOST_CONTROL RESOLVE_AFK`, applying the
session's AFK preset (abstain / host-assigns). Disconnected players are auto-flagged AFK.

**Vote lock:** `CAST_VOTE` writes into `GameState.votes` only if absent for that voter;
a second `CAST_VOTE` returns `ERROR {code: VOTE_LOCKED}`. Enforced in the pure reducer,
not the transport.

**Idempotency:** every `PLAYER_ACTION` carries a client-generated `actionId`; the
reducer records applied ids in `GameState` and no-ops duplicates (reconnection resends).

**Secret-data guarantee (CI-gated):** a contract test runs a full session, subscribes a
fake Faithful client + a fake broadcast client, and asserts no frame ever contains a
`role` field for another player before the `RESULTS` event. Gates merge.

---

## 5. Repository layout (monorepo)

```
truearena/
├── backend/                     # Maven multi-module, Java 21
│   ├── pom.xml                  # parent (spring-boot-starter-parent), <modules>
│   ├── ta-app/
│   ├── ta-api/
│   ├── ta-ws/
│   ├── ta-engine/               # no Spring
│   ├── ta-game-truearena/
│   ├── ta-room/
│   ├── ta-voice/
│   ├── ta-persistence/          # Flyway migrations: src/main/resources/db/migration
│   └── ta-contract-tests/
├── app/                         # Flutter (iOS + Android)
│   ├── lib/
│   │   ├── core/                # ws client, session, envelope codec
│   │   ├── features/{auth,groups,lobby,game,results}/
│   │   └── design/              # theme, phase transitions, emoji-burst widget
│   └── test/
├── shared/
│   └── contract/                # JSON schema for the WS envelope + event types;
│                               # codegen → Java records (ta-ws) + Dart classes (app)
├── infra/
│   ├── docker-compose.yml       # postgres, redis, livekit, backend, sms-stub
│   ├── livekit.yaml
│   ├── k8s/                     # (or terraform/, pick one)
│   └── grafana/
├── .github/workflows/ci.yml
└── docs/ARCHITECTURE.md         # this file
```

**Contract codegen** (`shared/contract`): one JSON-schema source of truth for the
envelope and every event `type`; a build step emits Java records into `ta-ws` and Dart
classes into `app/lib/core`. Prevents client/server wire drift — the most common
multiplayer bug.

---

## 6. Local development — one command

`docker compose -f infra/docker-compose.yml up`:

| Service | Image | Port | Notes |
|---|---|---|---|
| postgres | `postgres:16` | 5432 | Flyway runs on backend boot |
| redis | `redis:7` | 6379 | `notify-keyspace-events Ex` in command |
| livekit | `livekit/livekit-server` | 7880/7881 | dev keys in `livekit.yaml` |
| backend | built from `backend/` | 8080 | `SPRING_PROFILES_ACTIVE=local`, DevTools hot-reload |
| sms-stub | tiny HTTP echo | 8025 | logs OTP codes to stdout |

Flutter runs on the host (`flutter run`) pointed at `http://localhost:8080` /
`ws://localhost:8080`; a `--dart-define` swaps in a LAN IP for real phones.

Dev auth shortcut: profile `local` accepts OTP code `000000` for any number.

Seed (`infra/seed.sql` or a `/dev/seed` endpoint): 6 test users, a "Friday Crew"
group, one room. The headless bot client fills seats to test 6–16 player games
without 16 devices.

---

## 7. CI/CD

**CI (`ci.yml`), every PR:**
1. `./mvnw verify -DskipITs` — compile + unit tests incl. `ta-engine` reducer tests + the secret-data contract test.
2. Testcontainers integration tests (real Postgres + Redis): `ta-room`, reconnection/replay, host migration.
3. `flutter analyze` + `flutter test`.
4. Contract codegen staleness check.
5. Build backend Docker image (no push).

**CD:**
- Merge to `main` → build + push backend image (`ghcr.io`), tag `sha` + `main`.
- Auto-deploy to **staging** (k8s rollout, or `docker compose` on one VM to start).
- **Production** = manual promotion of the staging image tag.
- Flyway runs on pod startup; migrations must be backward-compatible for one release
  (expand/contract) since pods roll gradually.
- Flutter: `main` builds → TestFlight / Play internal track via Fastlane.

---

## 8. Deployment shape (v1 — keep it small)

One modest managed Kubernetes cluster (or 2 VMs + managed DB/Redis if k8s is overkill):

| Piece | v1 sizing | Scale lever |
|---|---|---|
| backend | 2–3 pods, HPA on CPU + active-socket gauge | horizontal; state in Redis |
| Postgres | 1 managed primary + 1 read replica | replica for stats/history reads |
| Redis | managed, primary + replica, Sentinel/cluster-mode | shard by room id if needed |
| LiveKit | 1–2 nodes, separate node pool (WebRTC = bandwidth-heavy) | LiveKit distributed mode + TURN |
| LB | cloud L7, no stickiness required | — |

Observability: Micrometer → Prometheus → Grafana. Dashboards: active rooms,
phase-transition latency, WS reconnects/min, engine reducer p99, force-mute success
rate, events-flushed-to-Postgres lag. Structured JSON logs correlated on
`roomId`/`sessionId`/`seq`. Sentry (or equiv) on backend + Flutter.

---

## 9. Milestone → architecture mapping

| Milestone | Comes online |
|---|---|
| **A0** | monorepo, `docker-compose.yml`, `ci.yml`, contract-schema skeleton |
| **A1** | `ta-api` (OTP, groups, rooms), `ta-room` (Redis registry, lobby, ready-check), `ta-ws` connect + `HELLO`/`SNAPSHOT` |
| **A2** | `ta-engine` (phases, timers via Redis key-expiry, event stream, reconnection replay), `GameConfig` on the wire |
| **A3** | `ta-game-truearena` reducer: roles, night, discussion, vote-lock, banishment, win checks + secret-data contract test |
| **A4** | vote-review reveal modes, AFK/tie preset resolution in the reducer, `HOST_CONTROL` handlers |
| **A5** | `ta-voice`: LiveKit tokens, webhook consumer, forced-mute on Vote phase |
| **A6** | session-end write-behind to Postgres, group stats endpoint + screen, rematch (new `Room`, same `Group`, carry roster) |

Track B later reuses `/ws/room/{id}` and `getBroadcastState` — no backend rework, just
a guest-token auth path and a React/Svelte client.

---

## 10. Deliberate seams for §11 (built now, cheap)

- `GameSession.game_type` + a `GameModule` registry keyed by string → a *second* game (Mafia, Secret-Hitler-style) is a registry entry, not a rebuild. The *Traitors and Faithful* modes are **not** separate games — they're preset `GameConfig`s of the one module (see below).
- `GameConfig` is an enumerated, versioned catalog of toggles + a twist registry; modes are `builtin` preset rows and custom games are `user`/`group` preset rows. New modes = new data. Full model: [GAME_CONFIG.md](GAME_CONFIG.md).
- Everything logged against `Group` with append-only `GameEvent` → group history / lore / seasons are read-side projections over data already stored.
- `PlayerStat` keyed `(group_id, user_id)` from day one → group-relative stat pages need no migration.
- `RandomSource` seed on the session → replays now; a home for future Chaos Mode random events.
- Outcome presets as a named, saved config object → the mode presets and host-authored custom games are the same `GameConfigPreset` shape; the twist catalog is versioned so old sessions replay under the catalog they started on.
