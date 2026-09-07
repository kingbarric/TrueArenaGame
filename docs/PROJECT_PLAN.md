# TrueArena — Implementation Plan (start → deployment)

> Companion to `docs/ARCHITECTURE.md` and the Build Brief. Ordered. Each phase is a
> vertical slice that leaves `main` green and demoable. Check a box only when its
> **Done when** conditions hold *and* its tests pass in CI.
>
> Legend: `[ ]` not started · `[~]` in progress · `[x]` done · 🔴 blocker for next phase

---

## Progress at a glance

| Phase | Title | Status |
|---|---|---|
| 0 | Foundations: monorepo, infra, CI | `[~]` |
| 1 | Data layer: Postgres schema + migrations + repos | `[~]` |
| 2 | Auth & accounts (phone + OTP) | `[~]` |
| 3 | Groups, friends, rooms (REST) | `[~]` |
| 4 | WebSocket transport, Redis room state, reconnection | `[ ]` |
| 5 | Game engine core (game-agnostic) | `[ ]` |
| 6 | TrueArena game module v1 | `[ ]` |
| 7 | Vote review + outcome presets | `[ ]` |
| 8 | Voice (LiveKit, audio-only, forced mute) | `[ ]` |
| 9 | Results, rematch, per-group stats | `[ ]` |
| 10 | Flutter app (runs alongside 2–9) | `[ ]` |
| 11 | Hardening, load test, observability | `[ ]` |
| 12 | Deployment: staging → production | `[ ]` |
| B0–B2 | Track B: web + host display + install funnel | `[ ]` |

---

## Running slice (verified locally, 2026-09-07)

A vertical slice of Phases 1–3 runs against Dockerised Postgres + Redis:

- **Swagger UI:** `http://localhost:8080/swagger-ui.html` · **OpenAPI:** `/v3/api-docs`
  (checked-in snapshots: [openapi.json](openapi.json) / [openapi.yaml](openapi.yaml))
- Endpoints live: `POST /api/v1/auth/otp/request|verify`, `POST /api/v1/auth/refresh`,
  `GET /api/v1/me`, `POST/GET /api/v1/groups`, `GET /api/v1/groups/{id}` + `/members`,
  `POST /api/v1/groups/{id}/members`, `POST /api/v1/rooms`, `POST /api/v1/rooms/join`,
  `GET /api/v1/rooms/{id}` — plus `/actuator/health`.
- Auth: phone+OTP → HS256 JWT (access 15m / refresh 30d); dev bypass code `000000`
  under `SPRING_PROFILES_ACTIVE=local`. `WebFilter` + reactive `SecurityWebFilterChain`
  guards `/api/**`; Swagger/actuator/`/api/v1/auth/**` are public.
- Flyway `V1__core.sql` + `V2__rooms.sql` apply on boot. R2DBC repos + services in
  `ta-api`. OTP codes in Redis (`otp:{phone}`, 5-min TTL).

**How to run it**

```bash
docker compose -f infra/docker-compose.yml up -d postgres redis   # host ports 5433 / 6380
cd backend && ./mvnw -q -DskipTests -pl ta-app -am package
SPRING_PROFILES_ACTIVE=local \
  R2DBC_URL=r2dbc:postgresql://localhost:5433/truearena \
  JDBC_URL=jdbc:postgresql://localhost:5433/truearena \
  DB_USERNAME=truearena DB_PASSWORD=truearena REDIS_PORT=6380 \
  java -jar ta-app/target/truearena-backend.jar
```

**Still stubbed / TODO before ticking the phase boxes**

- No Testcontainers slice tests yet (Phases 1.1–1.4, 2.1–2.4, 3.1–3.3 "Tests").
- `RoomView.createdAt` is null on the create response (R2DBC doesn't re-read DB
  defaults on `save`); populated on subsequent `GET`.
- `RoomView.sessionToken` reuses the access token — real room-scoped tokens + the
  Redis room registry (`room:{id}:*`) land in Phase 3.4 / 4.
- Refresh tokens aren't revocable yet; group `addMember` allows any member (owner-only
  check is Phase 3.1).
- Compose host ports moved to **5433** (pg) and **6380** (redis) to avoid clashing
  with services already bound to 5432/6379 on this machine.

---

## Phase 0 — Foundations

**Goal:** anyone can clone, `docker compose up`, and hit a health endpoint. CI runs on PRs.

- [x] **0.1 Monorepo skeleton**
  - `backend/` (Maven multi-module, Java 21, Spring Boot 3.3), `app/` (Flutter), `shared/contract/`, `infra/`, `docs/`.
  - Root `README.md` with the one-command dev instructions.
  - **Done when:** `./mvnw verify -DskipITs` and `flutter --version` both succeed on a clean checkout.
  - **Tests:** a trivial `ContextLoads` Spring test; `flutter test` on the default counter test.
  - _Status: `./mvnw verify -DskipITs` green (JDK 21, Maven wrapper committed, script-only). Flutter project is Dart-level only — run `flutter create .` once to add platform folders (see app/README.md); not verified on a machine without Flutter._

- [x] **0.2 Maven module split**
  - Modules: `ta-app`, `ta-api`, `ta-ws`, `ta-engine` (no Spring), `ta-game-truearena`, `ta-room`, `ta-voice`, `ta-persistence`, `ta-contract-tests`.
  - `ta-engine` has **no** `org.springframework` dependency (enforced by a dependency-check test or ArchUnit rule).
  - **Done when:** modules compile, `ta-app` wires an empty context.
  - **Tests:** ArchUnit rule `ta-engine must not depend on Spring`; module graph builds.
  - _Status: all 9 modules compile; `NoSpringInEngineTest` (ArchUnit) + `ContextLoadsTest` (infra autoconfig excluded) green. surefire excludes `@Tag("integration")`; failsafe runs them on `./mvnw verify`._

- [~] **0.3 Docker Compose dev stack**
  - Services: `postgres:16`, `redis:7` (with `notify-keyspace-events Ex`), `livekit/livekit-server`, `backend`, `sms-stub`.
  - `.env.example` with all config keys; `infra/livekit.yaml` with dev keys.
  - **Done when:** `docker compose -f infra/docker-compose.yml up` brings all services healthy; `GET /actuator/health` returns `UP`.
  - **Tests:** a smoke script (`infra/smoke.sh`) that curls health + checks Redis `PING` + `psql -c 'select 1'`.
  - _Status: `infra/docker-compose.yml`, `infra/livekit.yaml`, `backend/Dockerfile`, `.env.example`, `infra/smoke.sh` written. **Not yet run** (`docker compose up` + smoke) on this machine — first verification step for whoever picks this up._

- [~] **0.4 CI skeleton (`.github/workflows/ci.yml`)**
  - Jobs: `backend-build`, `backend-integration`, `secret-data-guarantee`, `flutter`, `contract-codegen-check`, `docker-build` (no push).
  - Branch protection on `main`: all jobs required.
  - **Done when:** a draft PR shows all jobs running and passing.
  - **Tests:** CI itself is the test; add one deliberately failing test on a scratch branch to confirm red blocks merge, then revert.
  - _Status: workflow written. Needs a GitHub remote + first PR to run; branch protection to be set in repo settings._

- [~] **0.5 Contract schema stub (`shared/contract/`)**
  - JSON Schema for the WS envelope `{ v, type, seq, ts, payload }` and an enum of message `type`s.
  - Codegen → Java records into `ta-ws/target/generated-sources/contract`, Dart classes into `app/lib/core/contract/`.
  - **Done when:** `./mvnw -pl ta-ws generate-sources` and `dart run tool/gen_contract.dart` both emit compiling code; `contract-codegen-check` fails if generated output is stale.
  - **Tests:** round-trip test — encode a sample envelope in Java, decode in a Dart test fixture (golden JSON files in `shared/contract/testdata/`).
  - _Status: `envelope.schema.json` + golden vectors done. Round-trip tests exist **both sides** (`EnvelopeRoundTripTest` in ta-ws — green; `envelope_test.dart` in app). `tools/check_contract.sh` validates vectors against the schema. **Deferred:** replace the hand-authored Java/Dart types with a real `generateContract` task so drift fails CI._

🔴 **Gate:** Phases 1+ require 0.1–0.5 green.

---

## Phase 1 — Data layer

**Goal:** every durable table from Architecture §2.3 exists, migrated, with reactive repositories and a seed path.

- [ ] **1.1 Flyway baseline migration `V1__core.sql`**
  - Tables: `users`, `friends`, `groups`, `group_members`.
  - Constraints: `friends` unique on ordered pair; `group_members` PK `(group_id, user_id)`.
  - **Done when:** Flyway migrates cleanly on an empty DB and is idempotent on restart.
  - **Tests:** Testcontainers Postgres — migrate, assert `information_schema` has the tables + constraints; migrate again, no error.
  - _Status: `V1__core.sql` drafted during Phase 0 (users, groups, group_members, friends). Still needs the Testcontainers migration test before checking._

- [ ] **1.2 Flyway `V2__rooms_sessions.sql`**
  - Tables: `rooms` (`group_id` nullable), `room_members`, `game_sessions` (with `rng_seed`), `roles`, `game_events` (append-only, `visibility_scope`), `votes`, `game_results`.
  - Indexes: `game_events (game_session_id, seq)`, `rooms (code)` unique.
  - **Done when:** migration applies; a manual insert of a full fake session succeeds.
  - **Tests:** Testcontainers — insert session → role → events → result graph; assert FK cascade behavior is what we want (events survive? decide and encode).

- [ ] **1.3 Flyway `V3__stats.sql`**
  - `player_stats` PK `(group_id, user_id)` with `group_id` nullable-sentinel handled via a partial unique index or a `NULL`-safe scheme (document the choice); columns: `games_played`, `wins`, `traitor_wins`, `traitor_games`, `times_suspected_first`, `updated_at`.
  - **Done when:** upsert (`INSERT ... ON CONFLICT`) works for both group-scoped and lifetime rows.
  - **Tests:** upsert twice, assert increment semantics; concurrent upsert test (2 threads) stays consistent.

- [ ] **1.4 R2DBC repositories + domain records**
  - `ta-persistence`: `UserRepository`, `GroupRepository`, `GroupMemberRepository`, `RoomRepository`, `GameSessionRepository`, `GameEventRepository`, `GameResultRepository`, `PlayerStatRepository`.
  - Reactive (`Mono`/`Flux`), no blocking calls (enforced by BlockHound in tests).
  - **Done when:** each repo has a passing CRUD test.
  - **Tests:** Testcontainers slice tests per repo; BlockHound active in the test JVM.

- [ ] **1.5 Seed fixture**
  - `/dev/seed` endpoint (profile `local` only) + `infra/seed.sql`: 6 users, "Friday Crew" group, one room.
  - **Done when:** hitting `/dev/seed` twice is safe (truncate-and-reload or upsert).
  - **Tests:** integration test calls `/dev/seed`, asserts row counts.

🔴 **Gate:** Phase 2 needs 1.1 + 1.4.

---

## Phase 2 — Auth & accounts

**Goal:** phone + OTP once, JWT access/refresh, `/me`.

- [ ] **2.1 OTP request/verify**
  - `POST /api/v1/auth/otp/request { phone }` → stores a hashed code in Redis with TTL, calls the SMS port (stub in `local`, pluggable provider iface).
  - `POST /api/v1/auth/otp/verify { phone, code }` → creates `users` row on first verify, returns `{ accessToken, refreshToken, user }`.
  - Profile `local`: code `000000` always verifies.
  - Rate-limit: max N requests per phone per window (Redis counter).
  - **Done when:** full request→verify→token flow works against the stub.
  - **Tests:** IT happy path; wrong code rejected; expired code rejected; rate-limit trips at N+1; second verify of same phone returns the same user id.

- [ ] **2.2 JWT issuance + validation filter**
  - Access token 15 min, refresh token 30 days (stored hashed, revocable).
  - `POST /api/v1/auth/refresh`; reactive `SecurityWebFilterChain`.
  - **Done when:** protected route returns 401 without token, 200 with a valid one.
  - **Tests:** expired access token → 401; refresh rotation invalidates the old refresh token; tampered signature → 401.

- [ ] **2.3 `GET /api/v1/me`**
  - Returns the authenticated `User`.
  - **Done when:** returns correct user; 401 when unauthenticated.
  - **Tests:** IT with a seeded user + minted token.

- [ ] **2.4 Guest token path (for Track B later, built now)**
  - Scoped token: `roomId` + nickname, no phone; cannot call group/friend endpoints.
  - **Done when:** guest token authorizes only `rooms/{id}` read + WS connect for that room.
  - **Tests:** guest token rejected on `/groups`; accepted on its room's WS.

---

## Phase 3 — Groups, friends, rooms (REST)

**Goal:** create a group, add members, create/join a room, get a join code.

- [ ] **3.1 Groups CRUD**
  - `POST /groups`, `GET /groups/{id}`, `GET /groups` (mine), `POST /groups/{id}/members`, `DELETE /groups/{id}/members/{userId}`.
  - Authorization: only members can read; only `created_by` (or admin role) can add/remove.
  - **Done when:** endpoints enforce membership rules.
  - **Tests:** non-member gets 403; creator adds a member; removed member loses access.

- [ ] **3.2 Friends**
  - `POST /friends/request`, `POST /friends/{id}/accept`, `GET /friends`.
  - **Done when:** request→accept transitions status; duplicate request is a no-op.
  - **Tests:** state machine transitions; can't accept someone else's request.

- [ ] **3.3 Rooms**
  - `POST /rooms { groupId?, config? }` → `rooms` row, 6-char join code (collision-checked), `wsUrl`, `sessionToken`.
  - `POST /rooms/join { joinCode, nickname? }` → adds `room_members`, returns `wsUrl` + `sessionToken`.
  - `GET /rooms/{id}` → room + members, **no secret state**.
  - **Done when:** create + join round-trips; codes are unique; ad-hoc room (no group) works.
  - **Tests:** join with bad code → 404; join a full room → 409; group room rejects non-group-members if `groupId` set and room is private.

- [ ] **3.4 Redis room registry (`ta-room`)**
  - On room create: write `room:{id}:meta`, `room:{id}:members`; set 6h sliding TTL.
  - Session token → `session:{token}` (userId + roomId).
  - **Done when:** REST create populates Redis; `GET /rooms/{id}` reads members from Redis, not Postgres.
  - **Tests:** create → assert Redis keys; TTL is set; token resolves.

🔴 **Gate:** Phase 4 needs 3.3 + 3.4.

---

## Phase 4 — WebSocket transport + reconnection

**Goal:** a client connects, gets a snapshot, receives events, and can drop/resume without losing state. No game logic yet — a stub "echo phase" machine.

- [ ] **4.1 WS handshake `/ws/room/{roomId}?session={token}`**
  - Validate token against `session:{token}`; bind socket to `RoomMember`; reject bad/expired token with close code.
  - **Done when:** valid token connects, invalid closes with a defined code.
  - **Tests:** IT with a real WS client (Spring `ReactorNettyWebSocketClient`); bad token closes 4401.

- [ ] **4.2 Envelope codec + `HELLO`/`SNAPSHOT`**
  - Client sends `HELLO { lastSeq }`; server replies `SNAPSHOT` (stubbed state) + `PHASE`.
  - **Done when:** connect → HELLO → SNAPSHOT observed.
  - **Tests:** malformed envelope → `ERROR`, socket stays open; unknown `type` → `ERROR`.

- [ ] **4.3 Redis event stream + pub/sub fan-out**
  - `XADD room:{id}:events`; `PUBLISH room:{id}:channel`; every pod subscribed pushes new events to its local sockets.
  - `seq` = stream id.
  - **Done when:** two sockets on (simulated) two pods both receive an appended event.
  - **Tests:** IT with two `ta-app` instances sharing one Redis (Testcontainers), or two subscriber registries in one JVM; assert both get the event once, in order.

- [ ] **4.4 Room mutation lock**
  - `SET NX lock:room:{id} PX 5000` around load→reduce→persist→publish; retry/backoff on contention.
  - **Done when:** 50 concurrent actions on one room produce a linear, gap-free `seq`.
  - **Tests:** concurrency test firing N actions from N threads; assert `seq` is `1..N` with no dupes/gaps.

- [ ] **4.5 Reconnection: replay vs fresh snapshot**
  - `HELLO { lastSeq }`: if `lastSeq` still in the stream → replay `EVENT`s after it; else → `SNAPSHOT`.
  - Stream trimmed with `XADD ... MAXLEN ~ 10000`.
  - **Done when:** kill a socket mid-stream, reconnect, client state matches a never-disconnected peer.
  - **Tests:** IT: connect A+B, emit 100 events, drop B at event 40, reconnect B, assert B's final state == A's; force trim, assert B gets SNAPSHOT not partial replay.

- [ ] **4.6 Phase timer via Redis key-expiry + sweep**
  - `SET room:{id}:phase <name> PX <ms>`; keyspace-notification listener advances phase; 2s scheduled sweep reconciles missed expiries.
  - **Done when:** stub machine auto-advances Lobby→EchoA→EchoB on timers.
  - **Tests:** IT with short timers (200ms); assert transitions fire; simulate a dropped notification (disable listener) and confirm the sweep still advances within ~2s.

- [ ] **4.7 Host migration**
  - Host WS close / LiveKit `participant_left` → pick longest-connected member → update `hostId` → emit `HOST_CHANGED`.
  - **Done when:** dropping the host promotes another member; game (stub) keeps running.
  - **Tests:** IT: 3 members, drop host, assert `HOST_CHANGED` names the expected member; host-only command from old host now rejected.

🔴 **Gate:** Phase 5 needs 4.2–4.6.

---

## Phase 5 — Game engine core (game-agnostic)

**Goal:** `ta-engine` provides the `GameModule` SPI, a pure reducer pipeline, deterministic RNG, and event derivation. Still no TrueArena rules — a `DummyModule` proves the contract.

- [ ] **5.1 SPI types**
  - `GameModule`, `GameConfig`, `GameState`, `PlayerAction`, `Phase`, `WinResult`, `PlayerVisibleState`, `PublicBroadcastState`, `GameEvent`, `RandomSource`.
  - Immutable records; `GameState` carries applied `actionId`s for idempotency.
  - **Done when:** compiles in a Spring-free module; published as an API jar.
  - **Tests:** none yet (types only) — covered by 5.2+.

- [ ] **5.2 Reducer harness**
  - `GameRunner`: `apply(state, action) -> (state', events)`, `elapse(state, phase) -> (state', events)`, calls `checkWinCondition` after each.
  - **Done when:** `DummyModule` (count taps, win at 3) runs a full game through the harness.
  - **Tests:** property test — applying the same action twice (same `actionId`) is a no-op; event list equals `drainEvents(prev,next)`.

- [ ] **5.3 Deterministic RNG**
  - `RandomSource` seeded from `game_sessions.rng_seed`; same seed + same actions → identical state.
  - **Done when:** replay test passes.
  - **Tests:** run DummyModule twice with a fixed seed and identical action log; assert byte-identical final `GameState` JSON.

- [ ] **5.4 Visibility filtering enforcement**
  - `getVisibleStateFor` and `getBroadcastState` run **after** fan-out, per subscriber, in `ta-ws`.
  - `GameEvent.visibility_scope` respected: `PUBLIC` / `ROLE:<x>` / `PLAYER:<id>`.
  - **Done when:** DummyModule marks one event `PLAYER:p1`; only p1's socket receives it.
  - **Tests:** IT: p1 sees the private event, p2 and broadcast do not; assert no `role`-like field leaks in any frame (generic guard).

- [ ] **5.5 `GameConfig` plumbing end-to-end**
  - Lobby `CONFIG_SET` (host only) → validated against the module's config schema → stored in `room:{id}:meta` → passed to `initialState`.
  - **Done when:** invalid config rejected with field-level `ERROR`; valid config reaches `initialState`.
  - **Tests:** out-of-range value rejected; non-host `CONFIG_SET` rejected; config persists across a host reconnect.

- [ ] **5.6 Session lifecycle + event archival**
  - On `GAME_START`: create `game_sessions` row (+ seed). During play: incremental flush of `game_events` to Postgres every N events. On end: final flush + `game_results`.
  - **Done when:** a completed DummyModule game leaves a full `game_events` trail + `game_results` in Postgres.
  - **Tests:** IT: play to a win, assert Postgres event count == Redis stream length; kill the app mid-game, restart, assert no double-write on resume.

🔴 **Gate:** Phase 6 needs all of Phase 5.

---

## Phase 6 — TrueArena game module v1

**Goal:** real roles, night, discussion, vote (with lock), banishment, win conditions. Brief §9.1–9.2.

- [ ] **6.1 Phase definition + config schema**
  - `definePhases`: Lobby → RoleReveal → (Night → Discussion → Vote → VoteReview → Banishment)* → Results.
  - `GameConfig`: traitor ratio/count, night/discussion/vote timers, vote reveal mode. Defaults + ranges from §9.1.
  - **Done when:** `definePhases` returns the right sequence for a given player count; defaults match the table.
  - **Tests:** table-driven test over player counts 6–16 → expected default traitor counts (§9.1 table); every timer default/range enforced.

- [ ] **6.2 Role assignment (RoleReveal)**
  - Seeded shuffle assigns Traitor/Faithful per config; writes `roles` rows; emits per-player `ROLE_ASSIGNED` events scoped `PLAYER:<id>`.
  - **Done when:** counts correct; each player's reveal is private.
  - **Tests:** N-run distribution test (seeded) → exact traitor count every time; **secret-data test**: Faithful socket + broadcast never receive another player's `role` before Results (this is the §8 non-negotiable — gates merge).

- [ ] **6.3 Night phase**
  - Traitors submit a shared target (`NIGHT_TARGET`); resolution on timer or all-traitors-submitted; emits `PLAYER_ELIMINATED` (public) at phase end.
  - Non-traitor `NIGHT_TARGET` rejected.
  - **Done when:** target dies, reveal happens at Discussion start.
  - **Tests:** two traitors disagree → last-write or majority rule (pick one, document); non-traitor action rejected; timer with no submission → configurable no-kill or random (per rules — document).

- [ ] **6.4 Discussion (Round Table) + host controls**
  - Open floor; `HOST_CONTROL`: `MUTE`/`UNMUTE` (one player), `EXTEND_TIMER`, `CUT_TIMER`, `ADVANCE_PHASE`.
  - **Done when:** each host control changes state/timer as specified; non-host rejected.
  - **Tests:** each control has a test; `EXTEND_TIMER` updates `phase_ends_at` and the Redis PEXPIRE; `ADVANCE_PHASE` jumps to Vote immediately.

- [ ] **6.5 Vote phase + vote lock**
  - On phase enter: emit `MICS_FORCE_MUTED` (consumed by `ta-voice` in Phase 8).
  - `CAST_VOTE { target }`: recorded only if voter has no vote yet; second attempt → `ERROR VOTE_LOCKED`.
  - Host UI feed: `VOTE_PROGRESS { n, m }` (counts only, no targets).
  - **Done when:** votes lock; progress event carries no target info.
  - **Tests:** re-vote rejected; `VOTE_PROGRESS` payload has no `target`/`voter` mapping; dead players can't vote; self-vote allowed/denied per rule (document).

- [ ] **6.6 Banishment + role reveal**
  - After VoteReview (Phase 7 wires the reveal UI; here just the tally): highest-voted player banished, their role emitted publicly.
  - **Done when:** correct player removed; role now public; loop continues.
  - **Tests:** clear majority banishes the right player; banished player's socket goes to spectator state.

- [ ] **6.7 Win conditions**
  - Faithful win: all Traitors banished. Traitors win: Traitors ≥ remaining Faithful.
  - Checked after every banishment and every night kill.
  - **Done when:** both win paths terminate the game into Results.
  - **Tests:** scripted games → each win condition; edge: last traitor banished same round a faithful is night-killed → Faithful still win (assert order of checks).

- [ ] **6.8 Full happy-path integration**
  - 7-player scripted game (2 traitors) start→Results via the WS contract, driven by the headless bot client.
  - **Done when:** deterministic seeded run produces a stable `game_results` + full event log.
  - **Tests:** golden-file test on the event log (seeded); re-run must match.

🔴 **Gate:** Phase 7 builds on 6.5/6.6.

---

## Phase 7 — Vote review + outcome presets

**Goal:** Brief §9.2 step 6 and §9.3 — reveal modes, tie presets, AFK presets, custom saved presets.

- [ ] **7.1 Vote review reveal modes**
  - `Sequential`: host `HOST_CONTROL REVEAL_NEXT` reveals one vote at a time. `AllAtOnce`: all revealed on phase enter.
  - **Done when:** both modes emit `VOTE_REVEALED` events in the right cadence.
  - **Tests:** sequential needs N `REVEAL_NEXT` calls; all-at-once emits N reveals immediately; non-host `REVEAL_NEXT` rejected.

- [ ] **7.2 Tie presets**
  - `Revote`, `NoElimination`, `RandomAmongTied`, `SuddenDeathDiscussion` (30s + revote), `HostDecides` (`HOST_CONTROL BREAK_TIE`).
  - Selected in `GameConfig`.
  - **Done when:** each preset resolves a tie deterministically (seeded where random).
  - **Tests:** one test per preset with a forced 2-2 tie → expected outcome; `SuddenDeath` inserts a real timed sub-phase; `HostDecides` waits for host and rejects others.

- [ ] **7.3 AFK / hesitant-vote presets**
  - Grace cutoff emits `AFK_PENDING { playerIds }`. `Abstain` (default) or `HostAssigns` (`HOST_CONTROL RESOLVE_AFK { playerId, target? }`).
  - Disconnected players auto-flagged AFK immediately.
  - **Done when:** a game never stalls on one silent player.
  - **Tests:** timer expiry with 1 non-voter → abstain path completes; host-assign path records the assigned vote; disconnected mid-vote → immediate AFK flag.

- [ ] **7.4 Custom named presets**
  - Host saves a `{ tiePreset, afkPreset, name }` combo (per user or per group); listed at lobby setup.
  - Composition only — no scripting (Brief §2).
  - **Done when:** saved preset reloads and pre-fills lobby config.
  - **Tests:** save → list → apply round-trip; invalid combo rejected; preset scoped correctly (not visible to other groups).

---

## Phase 8 — Voice (LiveKit)

**Goal:** audio-only voice bound to rooms; forced mute on Vote; host mute controls; webhook-driven presence.

- [ ] **8.1 Token minting (`ta-voice`)**
  - On lobby entry: `POST`-less internal call issues a LiveKit join token (room = TrueArena room id, identity = userId, audio publish only).
  - **Done when:** Flutter/CLI client joins the LiveKit room with the minted token.
  - **Tests:** token has correct grants (room, canPublish audio, no video); expired token rejected by LiveKit (IT against the compose LiveKit).

- [ ] **8.2 Webhook consumer**
  - `POST /livekit/webhook` (signature-verified): `participant_joined`/`participant_left` → update `room:{id}:members.connection_status`.
  - **Done when:** presence in Redis tracks LiveKit reality; feeds host migration + AFK.
  - **Tests:** IT posts signed webhook payloads → Redis updated; bad signature → 401.

- [ ] **8.3 Forced mute on Vote**
  - Engine `MICS_FORCE_MUTED` event → `ta-voice` calls LiveKit `MutePublishedTrack` for all participants; `MICS_UNMUTED` on VoteReview → unmute.
  - **Done when:** entering Vote mutes everyone server-side; leaving restores.
  - **Tests:** IT: join 3 participants, drive to Vote, assert all tracks muted via LiveKit admin API; VoteReview restores; a late joiner during Vote is also muted.

- [ ] **8.4 Host discussion mute/unmute**
  - `HOST_CONTROL MUTE/UNMUTE { playerId }` → single-participant LiveKit mute.
  - **Done when:** host mutes one player without affecting others.
  - **Tests:** IT: mute p2, assert only p2 muted; non-host rejected.

- [ ] **8.5 Failure handling**
  - LiveKit unreachable → game still proceeds (voice degraded), `VOICE_DEGRADED` event surfaced to clients; retry with backoff.
  - **Done when:** killing LiveKit mid-game doesn't stall the state machine.
  - **Tests:** IT: stop LiveKit container during Discussion, assert game advances and clients get `VOICE_DEGRADED`.

---

## Phase 9 — Results, rematch, per-group stats

**Goal:** Brief §9.2 step 9 + A6.

- [ ] **9.1 Results screen data**
  - `RESULTS` event: `winning_side`, full role reveal, per-player outcome. `game_results` row persisted.
  - **Done when:** every completed game emits a complete `RESULTS` payload.
  - **Tests:** golden test on `RESULTS` for the seeded 7-player game; role reveal now includes everyone.

- [ ] **9.2 Stats aggregation (write-behind)**
  - At Results: upsert `player_stats` per `(group_id, user_id)` + lifetime `(user_id, NULL)` row. Metrics: `games_played`, `wins`, `traitor_wins`/`traitor_games` → win rate, `times_suspected_first` (first player to receive a vote in round 1).
  - **Done when:** stats reflect a played game for a group room and an ad-hoc room (lifetime only).
  - **Tests:** play 3 seeded games → assert exact counters; ad-hoc game touches only the lifetime row; concurrent Results for two rooms in the same group don't corrupt counters.

- [ ] **9.3 `GET /groups/{id}/stats`**
  - Per-group leaderboard: wins, traitor win rate, times-suspected-first, longest streak (basic).
  - Reads from the Postgres read replica where available.
  - **Done when:** endpoint returns ranked rows; group-relative phrasing supported (e.g. "82% of this group's games").
  - **Tests:** IT: seed known stats → assert ranking + percentages; non-member → 403.

- [ ] **9.4 Rematch**
  - `POST /rooms/{id}/rematch` → new `rooms` row, same `group_id`, carry the roster + last `GameConfig`, fresh join code optional.
  - **Done when:** one tap recreates the lobby with the same people.
  - **Tests:** IT: rematch carries members + config; a member who left is not re-added; ad-hoc rematch works without a group.

---

## Phase 10 — Flutter app

**Goal:** the v1 primary surface. Runs in parallel — each deliverable pairs with the backend phase that unblocks it.

- [ ] **10.1 App scaffold + design system** (parallel with Phase 0)
  - Routing, dark theme, phase-transition animation primitive, floating emoji-burst widget, WS client + envelope codec (generated), session storage.
  - **Tests:** widget tests for the emoji burst and phase-transition; golden tests for the theme.

- [ ] **10.2 Onboarding: phone + OTP** (needs Phase 2)
  - One-screen phone entry → OTP entry → token stored in secure storage.
  - **Tests:** widget test with a mocked auth API; `000000` dev path; error states (bad code, resend cooldown).

- [ ] **10.3 Groups + friends UI** (needs Phase 3)
  - Group list, create group, invite by phone/user, friends list.
  - **Tests:** widget tests against a fake API; navigation flow test.

- [ ] **10.4 Lobby** (needs Phase 3 + 4)
  - Join by code, ready-check, host config panel (traitor count, timers, reveal mode, tie/AFK presets), start button (host only).
  - **Tests:** widget tests for config validation UI; integration test against a running backend (`flutter drive`) doing create→join→ready→start.

- [ ] **10.5 In-game phases** (needs Phase 6 + 7)
  - Role reveal, night target picker (traitors only), discussion view with reactions + host controls, vote picker with lock, vote-review (sequential/all-at-once), banishment reveal.
  - **Tests:** per-phase widget tests with scripted `SNAPSHOT`/`EVENT` streams; a full `flutter drive` game against the backend + bot clients filling seats.

- [ ] **10.6 Voice integration** (needs Phase 8)
  - LiveKit client, audio-only, mic indicator, auto-mute reflected in UI on Vote.
  - **Tests:** manual device matrix (iOS + Android, 2 real devices); automated check that UI mic state follows `MICS_FORCE_MUTED`.

- [ ] **10.7 Results + rematch + group stats** (needs Phase 9)
  - Results screen, rematch button, per-group stats page.
  - **Tests:** widget tests; `flutter drive` end-to-end: game → results → rematch → second game.

- [ ] **10.8 Reconnection UX** (needs Phase 4.5)
  - Drop/resume banner, automatic `HELLO { lastSeq }`, state re-hydrate.
  - **Tests:** integration test toggling airplane mode equivalent (kill/restore socket) mid-game; assert UI recovers without a manual reload.

---

## Phase 11 — Hardening, load, observability

- [ ] **11.1 Observability**
  - Micrometer → Prometheus; Grafana dashboards: active rooms, phase-transition latency, WS reconnects/min, reducer p99, force-mute success rate, event-flush lag.
  - Structured JSON logs correlated on `roomId`/`sessionId`/`seq`. Sentry on backend + Flutter.
  - **Done when:** dashboards populate from a local load run.
  - **Tests:** assert key metrics are exported (`/actuator/prometheus` contains them); a log line carries all three correlation ids.

- [ ] **11.2 Load test**
  - Gatling/k6 scenario: 50 concurrent rooms × 8 players, full game loop, with reconnection churn.
  - Targets (tune): reducer p99 < 50ms, phase-transition drift < 500ms, zero `seq` gaps, no lock starvation.
  - **Done when:** targets met on a staging-sized box; report committed to `docs/loadtest/`.
  - **Tests:** the load run is the test; CI runs a small smoke version (2 rooms) nightly.

- [ ] **11.3 Chaos / resilience**
  - Kill a backend pod mid-game; kill Redis replica; kill LiveKit; drop keyspace notifications.
  - **Done when:** every case degrades gracefully per its phase spec (no room death, host migrates, voice degrades, sweep covers timers).
  - **Tests:** scripted chaos IT suite (Testcontainers pause/kill) — one test per failure mode.

- [ ] **11.4 Security pass**
  - Authz matrix test (every endpoint × role), JWT hardening, rate limits, LiveKit webhook signature, no PII in logs, `/dev/*` disabled outside `local`.
  - Run the `security-review` skill on the branch.
  - **Done when:** authz matrix test is exhaustive and green; review findings triaged.
  - **Tests:** parametrized authz test; a test asserting `/dev/seed` returns 404 under profile `staging`.

- [ ] **11.5 Secret-data guarantee — final gate**
  - Dedicated CI job runs the §8 contract test across: RoleReveal, Night, Discussion, Vote, VoteReview, Banishment — Faithful client + broadcast client never see another player's role pre-Results.
  - **Done when:** job is required on `main` and green.
  - **Tests:** the job itself; add a deliberate leak on a scratch branch to prove it fails, then revert.

---

## Phase 12 — Deployment

- [ ] **12.1 Backend image + registry**
  - Multi-stage Dockerfile, non-root, JRE 21, healthcheck. Push to `ghcr.io` on merge to `main`, tags `sha` + `main`.
  - **Done when:** CI pushes an image; `docker run` of it serves `/actuator/health`.
  - **Tests:** CI job pulls the pushed image and smoke-tests it.

- [ ] **12.2 Staging environment**
  - Managed Postgres (+ replica), managed Redis (Sentinel), LiveKit node(s) on a separate pool, backend 2 pods behind an L7 LB, TLS.
  - Config via env/secrets manager; Flyway runs on pod start (expand/contract discipline).
  - **Done when:** merge to `main` auto-deploys; a full game plays through staging from two real devices.
  - **Tests:** post-deploy smoke job (health + seed + one bot game); manual 2-device playtest checklist in `docs/deploy/staging-checklist.md`.

- [ ] **12.3 Migration safety**
  - Rule + CI check: each migration is backward-compatible for one release; rollout is gradual.
  - **Done when:** a canary deploy with mixed old/new pods serves traffic with no errors.
  - **Tests:** CI runs the previous release's tests against the new schema; canary IT with two image versions.

- [ ] **12.4 Production environment**
  - Same shape as staging, sized per Architecture §8. Manual promotion of the staging image tag. HPA on CPU + active-socket gauge.
  - Runbooks: host-migration storm, Redis failover, LiveKit node loss, rollback.
  - **Done when:** production serves a real invited playtest (8+ players); dashboards + alerts live.
  - **Tests:** production smoke job (non-destructive); on-call alert test (trip a synthetic threshold).

- [ ] **12.5 Mobile release pipeline**
  - Fastlane: `main` → TestFlight + Play internal. Versioning tied to backend contract version.
  - **Done when:** a tester installs from TestFlight/Play and completes a game against production.
  - **Tests:** CI builds signed artifacts; a `flutter drive` run against staging gates the upload.

🔴 **v1 launch gate:** Phases 1–12 checked, 11.5 green, a full external playtest completed, trademark/app-store name check done (Brief §3).

---

## Track B — Web + host display (after Track A core loop is solid)

- [ ] **B0.1 Web player client** — React or Svelte, portrait, nickname + code join (guest token from Phase 2.4), same WS contract. Tests: e2e (Playwright) join→play a round.
- [ ] **B0.2 Host/broadcast display** — landscape, consumes `getBroadcastState` only, no private info ever rendered. Tests: assert no role data in the DOM at any phase; visual-regression snapshots.
- [ ] **B1.1 Broadcast polish** — stream-safe layout, emoji-reaction bursts, phase transitions legible at a glance. Tests: legibility checklist; snapshot tests.
- [ ] **B2.1 Install-conversion flow** — end-of-round "continue with your friends in the app" + claim-profile prompt (link guest → phone account). Tests: e2e guest→claim→same stats carried; analytics event fires.

---

## Standing testing conventions

- **Unit** (`ta-engine`, reducers, Dart logic): pure, fast, no I/O. Property tests for idempotency + determinism.
- **Slice/IT** (`ta-persistence`, `ta-room`, `ta-ws`): Testcontainers Postgres + Redis; BlockHound on; real WS client.
- **Contract**: golden JSON in `shared/contract/testdata/`, encoded one language / decoded the other.
- **Engine goldens**: seeded full-game event logs; a diff is a deliberate rule change + a PR note.
- **E2E**: `flutter drive` (app) and Playwright (web) against a running backend with headless bot clients filling seats.
- **CI required on `main`**: backend build+unit, backend IT, flutter analyze+test, contract-codegen-check, **secret-data guarantee** (11.5), docker-build.
- **Nightly**: small load smoke (11.2), chaos suite (11.3).
- Every checkbox above is "done" only when its listed tests exist and pass in CI.
