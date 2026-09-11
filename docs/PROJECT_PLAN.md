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
| 5 | Game engine core (game-agnostic) | `[~]` |
| 6 | TrueArena game module v1 | `[~]` |
| 7 | Config catalog: modes, twists, Veiled Endgame, custom games | `[~]` |
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
- Flyway `V1`–`V4` apply on boot (full schema: docs/DATABASE.md). R2DBC repos + services in
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

### Engine + first game (verified locally, 2026-09-10)

- **`ta-engine`** SPI built: `GameConfig` (catalog + `ConfigVocab` enums), `GameModule`,
  `GameState`, `PlayerAction`, `GameEvent` (+ `Visibility`), `Phase`, `WinResult`,
  `RandomSource` (seeded), `GameRunner`. `NoSpringInEngineTest` still green.
- **`ta-game-truearena`** — the flagship module: `TrueArenaModule` (RoleReveal → Night →
  MorningReveal → RoundTable → Vote → VoteReview → Elimination → WinCheck → Results;
  seeded role assignment, night-kill cadence incl. `openingNight:"off"`, vote-lock,
  tie-break, alternating reveal, Veiled Endgame, win checks), `Presets` (the 5 modes as
  `GameConfig`), `ConfigValidator` (GAME_CONFIG.md §8), `TwistRegistry` (12 ids +
  metadata; `hidden_legacy` wired), `AutoPlay` (deterministic bot game).
- **Tests:** `TrueArenaEngineTest` (8: role counts, vote-lock, self-vote, idempotency,
  every preset plays to a terminal result, determinism, hidden_legacy fires),
  `SecretDataGuaranteeTest` (§8 — 75 seeded full games audit every Faithful/broadcast
  frame + event for a foreign role), `ConfigValidatorTest` (6).
- **Schema (`V1`–`V4`, normalized 2026-09-10)**: `game_config_preset`, `game_sessions`
  (`config`/`config_preset_id`/`catalog_version`/`phase_ends_at`), `roles`, `game_events`,
  `votes`, `game_results`, `player_stats`. Every enum-like column has a `CHECK`; the
  preset table has a scope↔owner↔slug `CHECK`; `player_stats` uses
  `UNIQUE NULLS NOT DISTINCT`. `PresetSeeder` rewrites the 5 `builtin` rows on every
  boot. Full column-level reference: **[DATABASE.md](DATABASE.md)**.
- **Endpoints:** `GET /api/v1/config/presets` (builtins + caller's saved), `GET /config/twists`,
  `POST /config/validate`, and (local) `POST /api/v1/dev/simulate` → runs a full
  deterministic game, returns winning side + public event log + final roles.
- **Caveat:** `ContextLoadsIT` (full wiring against Testcontainers PG+Redis) needs a
  Docker socket Testcontainers can see — locally set `DOCKER_HOST=unix://$HOME/.docker/run/docker.sock`;
  CI's ubuntu runner has `/var/run/docker.sock`. `./mvnw verify -DskipITs` (fast build) skips it.

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

**Goal:** every durable table exists, migrated, with reactive repositories and a seed
path. **Canonical schema: [DATABASE.md](DATABASE.md)** (migrations are the executable truth).

- [~] **1.1 Flyway `V1__core.sql` — accounts + social graph**
  - `users`, `groups`, `group_members`, `friends`. Enum-like columns carry `CHECK`s;
    `friends` ordered-pair unique + `requested_by ∈ pair`.
  - **Done when:** Flyway migrates cleanly on an empty DB and is idempotent on restart.
  - **Tests:** Testcontainers Postgres — migrate, assert `information_schema` has the
    tables + constraints; migrate again, no error.
  - _Status: written + verified to apply (V1–V4 clean on a fresh DB). Still needs the
    Testcontainers assertion test._

- [~] **1.2 Flyway `V2__rooms.sql` + `V3__game.sql`**
  - V2: `rooms`, `room_members`. V3: `game_config_preset`, `game_sessions`
    (`config`/`config_preset_id`/`catalog_version`/`rng_seed`/`phase_ends_at`), `roles`,
    `game_events` (`visibility_scope`/`_key` + the public⇔key CHECK), `votes`
    (`voter ≠ target`, unique per round), `game_results`. Full columns + CHECKs in
    [DATABASE.md](DATABASE.md).
  - _The 5 `builtin` preset rows are seeded from code by `PresetSeeder` (Phase 7.6)._
  - **Done when:** migrations apply; a manual insert of a full fake session succeeds.
  - **Tests:** Testcontainers — insert session → role → events → result graph; assert FK
    cascade + the CHECK constraints reject bad rows.
  - _Status: written + applied on a fresh DB; `PresetSeeder` inserts 5 builtins; the
    `game_config_preset` scope/owner CHECK verified to reject an illegal row._

- [ ] **1.3 Flyway `V4__stats.sql` — `player_stats`**
  - One row per `(group_id, user_id)`; `group_id IS NULL` = the user's lifetime rollup.
    `UNIQUE NULLS NOT DISTINCT (group_id, user_id)` (PG 15+). Counts only
    (`games_played`, `wins`, `traitor_games`, `traitor_wins`, `times_first_accused`,
    win-streak); rates derived in queries. Sanity CHECKs (`wins ≤ games_played`, …).
  - **Done when:** upsert (`INSERT ... ON CONFLICT`) works for both group-scoped and
    lifetime rows.
  - **Tests:** upsert twice, assert increment semantics; concurrent upsert (2 threads)
    stays consistent.
  - _Status: `V4__stats.sql` written + applied; repo/upsert logic is Phase 9.2._

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

- [ ] **2.4 Guest token path (device-id identity — for the funnel + Track B)**
  - `POST /api/v1/guest` with an `X-Device-Id` header → a short-lived, scoped guest JWT
    bound to that device id; no phone. Cannot call group/friend endpoints; can join one
    room + connect its WS. A lightweight guest user row (or `guest_session`) holds
    nothing durable.
  - **After one game, the guest's data clears** unless they verify — `POST /api/v1/guest/claim`
    with phone (preferred) or email → OTP → upgrades to a real account and re-parents the
    just-played session/stats. (Product fact: see the `guest-identity` memory.)
  - The Flutter app (`app/`) already generates + persists the device id and has the guest
    entry point; the backend side is not built yet.
  - **Done when:** guest token authorizes only its room; claim upgrades and keeps history.
  - **Tests:** guest token rejected on `/groups`; accepted on its room's WS; unclaimed
    guest data is purged after the session ends; claim links the session to the new account.

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

**Goal:** a client connects, gets a snapshot, receives events, and can drop/resume without losing state.

**Status: built and verified against the real engine, not the stub originally scoped here.** Phases 5–7 (the real `TrueArenaModule` engine) already existed and were fully tested by the time this phase started, so rather than build a throwaway "echo phase" machine and re-wire it later, this phase wires the WS transport directly to the real engine (`ta-engine` + `ta-game-truearena`). Verified 2026-09-11 with a Node.js script driving 6 real WebSocket connections (`ws://localhost:8080/ws/room/{roomId}?token=...`) through account creation → room join → `GAME_START` → a full `Night → RoundTable → Vote → Elimination → WinCheck` loop to `GAME_OVER`, asserting no client ever received another player's un-revealed role over the wire — the secret-data guarantee holds at the transport layer, not just inside the engine's own unit tests.

Three deliberate v1 simplifications versus the architecture doc's aspirational multi-pod design, all documented here rather than silently diverging:
- **State lives in-process per-pod** (`RoomRuntime`/`RoomRuntimeRegistry`, a `ConcurrentHashMap`), not serialized into Redis on every mutation. Fine for a single `ta-app` instance; a real multi-pod deploy needs state rehydration on the receiving pod, which isn't built.
- **Auth reuses the existing REST-issued access JWT** (`JwtService.parseAccess`) passed as a `?token=` query param, instead of a separate Redis `session:{token}` key.
- **Phase timers run as in-process `Mono.delay(...).subscribe(...)`** (`GameOrchestrator.rescheduleTimer`), not Redis keyspace-notification + sweep. Correct for one pod; a timer is lost if that pod restarts mid-phase.

- [x] **4.1 WS handshake `/ws/room/{roomId}?token={accessJwt}`**
  - `RoomWebSocketHandler` + `GameOrchestrator.authenticate()`: parses the JWT, verifies room membership via `RoomMemberRepository`, rejects with close code 4401 otherwise.
  - **Verified:** valid token connects and receives a lobby `SNAPSHOT`; the e2e script's 6 connections all authenticated correctly.

- [x] **4.2 Envelope codec + `HELLO`/`SNAPSHOT`**
  - `HELLO { lastSeq }` → lobby `SNAPSHOT` pre-game, or full `SNAPSHOT`/event replay once started.
  - **Verified:** end-to-end via the e2e script.
  - **Gap:** malformed-envelope and unknown-type IT coverage not yet automated (manually confirmed `BAD_ENVELOPE`/`UNSUPPORTED` `ERROR` codes exist in `GameOrchestrator.handleFrame`).

- [x] **4.3 Event log + fan-out (single-pod)**
  - `RoomEventLog` uses a Redis **LIST** (`RPUSH`/`LRANGE`), not Streams — the engine's `seq` is already a gap-free 1-based counter under the room lock, so list index `i` is exactly the event with `seq == i+1`. In-process fan-out is a `Sinks.Many` bus (`RoomRuntime.bus`) plus a per-connection unicast sink, not Redis pub/sub — so this **does not yet fan out across pods**, only across sockets on the same instance.
  - **Verified:** 6 simultaneous connections all receive the correct broadcast + role-scoped events.

- [x] **4.4 Room mutation lock**
  - `RoomLock`: Redis `SET NX PX` + 25ms poll-retry, 5s acquire timeout, 10s TTL.
  - **Bug found and fixed during verification:** `withLock`'s success path was `.flatMap(result -> release(key)...)`, which never fires for a `Mono<Void>` action (no `onNext` on empty completion) — `GAME_START`/`PLAYER_ACTION`/`triggerElapse` all return `Mono<Void>`, so the lock was never released and every action after the first timed out after 5s. Fixed with `.switchIfEmpty(Mono.defer(() -> release(key).then(Mono.empty())))`.
  - **Tests:** covered indirectly by the e2e script (sequential actions across a full game all succeeded post-fix); a dedicated concurrency IT (N threads, gap-free `seq`) is not yet written.

- [~] **4.5 Reconnection: replay vs fresh snapshot**
  - Implemented (`handleHello` replays `eventLog.replayAfter(lastSeq)` filtered by `visibleTo()`, or sends a full snapshot) but not exercised by the e2e script or an IT yet — no drop/reconnect-mid-game test has been run.

- [x] **4.6 Phase timers (in-process, single-pod)**
  - `GameOrchestrator.rescheduleTimer` cancels/reschedules a `Mono.delay` per `GameConfig` timer seconds; see the Redis-keyspace deviation noted above.
  - **Verified:** the e2e game's un-timed phases were advanced by explicit host `ADVANCE_PHASE` actions (matching how the real app's host UI will drive it); timer-elapse itself is implemented in `triggerElapse` but not exercised by an automated test yet.

- [ ] **4.7 Host migration**
  - `onDisconnect` → `migrateHost()` is implemented but has not been exercised by any test (manual or automated) yet.

🟢 Phase 5 gate (4.2–4.6) is met for a single-pod deployment; multi-pod fan-out (4.3) and reconnection/host-migration test coverage (4.5, 4.7) remain open follow-ups.

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
  - `definePhases`: `Lobby → RoleReveal → (Night → MorningReveal → RoundTable → Vote → VoteReview → Elimination → WinCheck)* → FinalFire → Results` (see [GAME_CONFIG.md](GAME_CONFIG.md) §2).
  - `GameConfig` = the full catalog: `table` (players/override/traitorCurve), `timers`, `nightKill` cadence (openingNight / doubleAfterRound / allowSkip / requireTraitorConsensus), `revealOnElimination`, tie/`secondTie`/AFK, `voteReveal`, `endgameVeil`, `twists{}`. Structure + enums: GAME_CONFIG.md §3–4.
  - **Done when:** `definePhases` returns the right sequence for a config; every enum + range validated per GAME_CONFIG.md §8.
  - **Tests:** table-driven over player counts 5–16 → traitorCurve resolves to the expected int; `openingNight:"off"` skips the round-1 kill; every timer/enum out-of-range rejected.

- [ ] **6.2 Role assignment (RoleReveal)**
  - Seeded shuffle assigns Traitor/Faithful per config; writes `roles` rows; emits per-player `ROLE_ASSIGNED` events scoped `PLAYER:<id>`.
  - **Done when:** counts correct; each player's reveal is private.
  - **Tests:** N-run distribution test (seeded) → exact traitor count every time; **secret-data test**: Faithful socket + broadcast never receive another player's `role` before Results (this is the §8 non-negotiable — gates merge).

- [ ] **6.3 Night phase + kill cadence**
  - Traitors submit a shared target (`NIGHT_TARGET`); resolution on timer or all-traitors-submitted (or all-confirmed if `requireTraitorConsensus`). `MorningReveal` announces the eliminated player and applies `revealOnElimination` (`always`/`never`/`alternating`).
  - Cadence from config: `openingNight:"off"` → no round-1 kill; `doubleAfterRound:R` → two targets allowed after round R; `allowSkip` → traitors may pass once per game.
  - Non-traitor `NIGHT_TARGET` rejected.
  - **Done when:** each cadence variant produces the right kills; MorningReveal reveal policy correct.
  - **Tests:** disagree → last-write or majority (pick + document); Final-Gambit config → silent opening night; Blood-Moon config → single kills R1–2 then optional double; skip consumed once only.

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

## Phase 7 — Config catalog: modes, twists, Veiled Endgame, custom games

**Goal:** the config-driven layer from [GAME_CONFIG.md](GAME_CONFIG.md) — reveal modes,
tie/AFK presets, the twist registry, the 5 modes as data, host-composed custom games,
and Veiled Endgame.

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

- [ ] **7.4 `TwistRegistry` + twist hooks**
  - `ta-game-truearena`: registry keyed by twist id for `catalogVersion` 1 — the 12 entries in [GAME_CONFIG.md](GAME_CONFIG.md) §5, each with a param schema + the phases it hooks.
  - Reducer consults `config.twists[id]` before the relevant phase hook; unknown id → config rejected.
  - Ship at least: `hidden_legacy`, `poisoned_gift`, `secret_accusation`, `last_will`, `trial_of_two`, `survivors_choice`, `immunity_coin`, `silent_witness` (the rest can land incrementally behind the same registry).
  - **Done when:** each shipped twist changes the game as specified, seeded/deterministic; disabling it is a true no-op.
  - **Tests:** per-twist scripted game; `hidden_legacy` recruits exactly when the trigger fires and never otherwise; **secret-data test still passes with every twist on**.

- [ ] **7.5 Veiled Endgame**
  - Once `livingPlayers ≤ endgameVeil` threshold, `VoteReview`/`Elimination` emit only `VOTE_LOCKED`, `ALL_VOTES_IN`, and the eliminated player; full ballot history released on `Results`.
  - **Done when:** the veil turns on at the right count for each mode and never leaks tallies/targets while on.
  - **Tests:** drive a game to the threshold → assert no `VOTE_REVEALED` payload carries a voter→target pair until `Results`; `endgameVeil:"off"` behaves as today.

- [ ] **7.6 Modes as data + custom games**
  - Flyway migration + seeder: `game_config_preset` (GAME_CONFIG.md §7); upsert the 5 `builtin` modes by `slug` from GAME_CONFIG.md §6.
  - `GET /config/presets` (builtins + caller's `user`/`group` presets); `POST /groups/{id}/presets` / `POST /me/presets` to save a host-composed `GameConfig` (scope `group`/`user`).
  - Lobby `CONFIG_SET` accepts a full `GameConfig`; server re-validates per GAME_CONFIG.md §8 (balance warning for out-of-range + `adminOverride`).
  - `game_sessions` gains `config JSONB` + `config_preset_id`.
  - **Done when:** pick a mode → edit → save as custom → reload → start; a session records the config it ran.
  - **Tests:** each builtin seed round-trips through the validator; out-of-range players blocked without `adminOverride`, allowed with; custom preset scoped correctly (invisible to other groups); unknown `catalogVersion` rejected.

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
