# TrueArena / Topskul — Session Handoff: Whot Card Game

Paste this file's content (or just reference its path) at the start of a new
session to pick up where this one left off. Written 2026-10-01.

## Why this file exists

The previous session ran on Opus and burned a week's usage in ~2 days (long
session, huge context, repeated builds/tests). Start the next session on
**Sonnet** (`/model sonnet`) for routine implementation work — it's more than
capable of the remaining Whot work — and reserve Opus for genuinely hard
design/reasoning calls.

## What Whot is and why it exists

User disliked the Goosi (mancala) game and asked to shelve it ("disable it
and say coming soon") and build **Whot** instead — a Nigerian card game,
2–20 players. This is now in progress.

### Goosi status
- `app/lib/features/games/game_select_screen.dart` and `home_screen.dart`:
  Goosi set `available: false` with comment "Shelved while the sowing game
  is reworked". Direct-open branches and lobby-screen imports removed.
- Backend module untouched — just not reachable from the UI.

## Whot: rules as confirmed by the user

- Any number of players, 2–20.
- Shapes: Circle, Triangle, Cross, Square, Star, plus Whot (wild).
- Deal ceremony (explicit user request): host **shuffles** (tap), then
  **manually deals** by tapping the deck N times (configurable cards per
  player, default 5), then taps **Start**. Not an instant auto-deal.
- Special cards, **all configurable, default ON**:
  - **2 — Pick Two**: next player draws 2. Stackable by default (another 2
    passes the penalty on and adds to it); a config flag can disable
    stacking, in which case the only answer to a 2 is to draw.
  - **14 — General Market**: everyone *except* the player who played it
    draws 1.
  - **1 — Hold On**: confirmed by user — **the player who played it goes
    again** (turn does not advance).
  - **8 — Suspension**: confirmed by user — **skips the next player**
    (advances by 2 instead of 1). User noted these two look identical with
    only 2 players, which is correct behavior, not a bug.
  - **20 — Whot**: wild; the player who plays it names the next shape.
    Configurable whether Whot cards are even in the deck (`includeWhot`,
    default true — many groups play without it).
- Deck composition (no 6s or 9s, historically missing from real Whot decks):
  - Circle & Triangle: {1,2,3,4,5,7,8,10,11,12,13,14} (12 cards each)
  - Cross & Square: {1,2,3,5,7,10,11,13,14} (9 cards each)
  - Star: {1,2,3,4,5,7,8} (7 cards)
  - 5 Whot cards (number 20)
  - Multiple decks are combined automatically for large player counts (up
    to 20 players).

## Open rules questions — NOT yet answered by the user

Ask these before building the scoring/end-of-round UI:

1. **What ends a round with many players?** Currently implemented: first
   player to shed their whole hand wins outright, everyone else just
   "loses". The alternative (common in real Whot with >2 players): round
   ends when one player empties their hand, then everyone else *scores*
   their remaining cards, and play continues across rounds to a target
   score. This determines whether a scoreboard/multi-round UI is needed.
2. **Does the Whot card itself count against you at the end?** Traditionally
   worth a heavy penalty (e.g. 20 points) if caught holding one. Only
   relevant if question 1 lands on scoring rather than shed-to-win.

## Backend state — DONE and verified

### New module: `backend/ta-game-whot/`
- `WhotCard.java` — `record WhotCard(Shape shape, int number)`, shapes
  `CIRCLE, TRIANGLE, CROSS, SQUARE, STAR, WHOT`, `WHOT_NUMBER = 20`,
  `code()`/`parse()` round-trip (e.g. `"circle-5"`).
- `WhotConfig.java` — all the toggles above, `WhotConfig.defaults()` is all
  true, 45s turn, 5-card starting hand.
- `WhotState.java` — hands kept in a `Map<String, List<WhotCard>>` (never
  exposed except to the owning player), market, pile, demandedShape,
  pendingPick, turnIndex, `Draft` builder.
- `WhotModule.java` — implements `GameModule`:
  - Phases: `Deal` → `Turn` → `Results`.
  - Actions: `SHUFFLE`, `DEAL` (dealer-only, `rounds` param 1-12 per tap),
    `START` (dealer-only, requires everyone ≥ `MIN_HAND=3`), `PLAY`, `DRAW`.
  - `DEAL_SECONDS = 120` auto-deal fallback if the dealer idles.
  - `MIN_PLAYERS=2`, `MAX_PLAYERS=20`, `MARKET_HEADROOM=24`.
  - Emits `YOUR_HAND` / `YOUR_DRAW` as **player-scoped events**
    (`d.emitToPlayer`) — never broadcast publicly. Public view only ever
    carries `handSizes` (counts), never the cards.
  - Finished-game actions are no-ops (idempotent replay safe), matching the
    pattern in other modules.
  - `applySpecial` implements the 2/14/1/8/20 rules above exactly as
    confirmed by the user.
- Tests: `WhotModuleTest.java` (13 tests — deck composition, player bounds,
  deal ceremony, dealer-only enforcement, reshuffle, idle-dealer auto-deal,
  hand secrecy) + `WhotSpecialsTest.java` (new — one test per special card
  and toggle combination, built on hand-constructed table positions rather
  than full games, same pattern as the Draughts/Goosi board tests).
  **All 28 tests pass.**

### Engine SPI change: `backend/ta-engine/.../GameModule.java`
Added a new **default method** (so nothing else needed to change):
```java
default boolean hasPrivatePlayerState() {
    return false;
}
```
Rationale: every other game here is played on an open board — the public
broadcast carries everything, and a per-player view only mattered on
join/reconnect. Whot is the first game where a player's hand changes on
*every* turn (yours and everyone else's) and can't ride the public frame.
`WhotModule` overrides this to `true`.

### Orchestrator wiring: `backend/ta-api/.../ws/GameOrchestrator.java`
- `afterMutation` now also calls a new `broadcastPrivateState(rt)`, which —
  only for modules where `hasPrivatePlayerState()` is true — re-sends each
  **connected, non-spectator** player (`rt.connectedUserIds` minus
  `rt.spectatorUserIds`) their own `visibleStateFor` snapshot after every
  action. This is what keeps every hand in sync without leaking anyone
  else's.
- `startWhot(rt, userId, playerIds)` added alongside `startGoosi` /
  `startDraughts` / `startWordBluff`, following the same pattern: reads
  per-room `gameConfig` via a new `whotConfigFrom(json)` (mirrors
  `goosiConfigFrom`/`draughtsConfigFrom`), falls back to
  `WhotConfig.defaults()` on null/blank/unreadable JSON.
- `GameOrchestrator`'s game-type switch now has `case "whot" ->
  startWhot(...)`.

### Room registration: `backend/ta-api/.../room/RoomService.java`
`GAME_TYPES` set now includes `"whot"`.

### Database migration: `backend/ta-persistence/.../V21__whot.sql`
**Important trap discovered**: the `rooms` table has a Postgres `CHECK`
constraint on `game_type` (`rooms_game_type_check`), separate from and in
addition to the Java-side `RoomService.GAME_TYPES` set. Adding a game type
to the Java set is **not enough** — a V-numbered migration must also widen
the DB check constraint, following the pattern of V8 (draughts) and V10
(goosi). V21 widens it to include `'whot'` while keeping `'goosi'` (shelved
in the UI, not removed from the DB).

### Docs: `docs/DATABASE.md`
The `rooms` table doc was missing `game_type`, `stake_coins`, and
`game_config` entirely (the V21 migration's "canonical reference" comment
pointed at a doc that didn't document the thing it was changing). Fixed:
added all three rows with correct types (`stake_coins` is `bigint` with a
`≥ 0` check, not `int`; `game_config` is `text` holding JSON, not `jsonb`),
and the `game_type` row now explicitly warns that each new game type needs
its own migration (points at V6/V8/V10/V21) — registering it in
`RoomService.GAME_TYPES` alone silently fails with a DB constraint
violation.

### Dependency wiring
- Root `pom.xml`: `ta-game-whot` module registered + added to
  `dependencyManagement`.
- `ta-api/pom.xml`: dependency on `ta-game-whot` added.

### Build/test status (last verified)
- `./mvnw clean package` — full suite green, including all 28 Whot tests.
- Live E2E (`whot_e2e.mjs`, written in scratchpad, **not yet copied into the
  repo** — see "Loose ends" below) — 21 assertions against a running
  server, passed 4 consecutive runs. Covers: room creation, join by code,
  dealer identification (seat order ≠ join order — the test reads
  `payload.dealer` from state rather than assuming the host deals),
  shuffle, non-dealer deal rejection (`NOT_THE_DEALER`), multi-round deal,
  hand secrecy end-to-end (no card held only by the opponent ever reaches
  your socket, verified by scanning every raw frame each side received),
  play/draw hand-size deltas, and — critically — that the player who did
  **not** move still receives a fresh private-state push after the other
  player's turn (proves `broadcastPrivateState` works for the non-actor).

### Local dev environment gotcha (not Whot-specific, but blocked testing)
This machine's TrueArena Postgres and Redis are **not on default ports**:
- Postgres: `localhost:5433` (5432 is taken by an unrelated `postgres_db`
  container)
- Redis: `localhost:6380` (6379 is taken by something else)

The backend needs these env vars to boot locally:
```bash
SPRING_PROFILES_ACTIVE=local \
R2DBC_URL='r2dbc:postgresql://localhost:5433/truearena' \
JDBC_URL='jdbc:postgresql://localhost:5433/truearena' \
REDIS_PORT=6380 \
java -jar ta-app/target/truearena-backend.jar
```
Worth writing a `run-local.sh` so this isn't rediscovered every session.
Check `docker ps` to confirm the actual container/port mapping hasn't
changed (`truearena-dev-postgres-1`, `truearena-dev-redis-1`).

**Note**: at the end of the previous session a background "Restart backend"
task failed (exit 143 = killed, likely by a `pkill` or the session ending)
— the backend may not be running when the next session starts. Restart it
with the command above before resuming any E2E testing.

## Not started yet — the actual remaining work

1. **Answer the two open rules questions above** (shed-to-win vs. scoring,
   Whot-card penalty) — this determines whether a scoreboard is needed.
2. **Bot adapter** for Whot (`WhotBotAdapter` or similar, mirroring
   `WordBluffBotAdapter`/draughts bot) — picks a legal card or draws, calls
   shape for Whot cards, decides whether to stack a 2.
3. **Flutter table UI** (`app/lib/features/whot/`, doesn't exist yet):
   - Lobby/pre-deal screen: shuffle button, tap-to-deal with a visible
     counter, start button — matching the ceremony described above.
   - Table screen: hand of cards fanned at the bottom (own hand only,
     obviously), discard pile, market (draw pile), turn indicator,
     shape-picker dialog for Whot cards, pick-two/general-market toast
     notifications.
   - **Card faces**: user has consistently wanted original art/geometric
     shapes drawn in code (same approach as other games here), not stock
     card images — circle/triangle/cross/square/star drawn as
     `CustomPainter`s, Whot drawn distinctly (e.g. rainbow/wild treatment).
   - Rule-toggle config screen for the host (mirrors Draughts/Goosi
     `game_config` settings screens) exposing all 6 `WhotConfig` booleans
     + starting hand size + turn seconds.
4. **Lobby entry**: `game_select_screen.dart` currently has Whot as
   `available: false` (placeholder) — flip it to `true` and wire the
   lobby/room-creation flow once the table screen exists.
5. Copy `whot_e2e.mjs` from the scratchpad into a permanent test location in
   the repo if the project keeps its E2E scripts under version control
   (check for an existing `e2e/` or `scripts/` convention first).

## Broader project context (for orientation, not urgent)

- Stack: Java 21, Spring Boot 3.3.5 WebFlux, R2DBC/Postgres, Flyway (now at
  **V21**), Maven multi-module backend; Flutter frontend.
- Other games live: TrueArena (Traitors/Faithful social deduction),
  Word Bluff, Draughts, Goosi (shelved in UI only).
- Known outstanding items from earlier in the project (not Whot-related,
  mentioned for completeness, not urgent):
  - `LlmMovePicker` (Gemini → Groq → Stub) has no runtime failover, only
    startup-time selection; Gemini free tier (500/day) was observed
    exhausted causing silent fallback to random moves. User asked about
    building a non-LLM legal-move bot (alpha-beta search) for Draughts
    instead — discussed but not started.
  - Security items flagged previously and still unresolved: `local` profile
    OTP dev-bypass code `"000000"` accepts any phone number (must not ship
    to a remote/public environment); `JWT_SECRET` and `LIVEKIT_API_SECRET`
    have dev-only defaults in `application.yml`.
  - A Gemini API key was shared in plaintext earlier in this project's
    history and should be treated as compromised/rotated if it hasn't been
    already (not stored in source — `application.yml` reads
    `${GEMINI_API_KEY:}` from env only).

## Suggested first message for the new session

> Continue the Whot card game backend work — see WHOT_HANDOFF.md in the
> repo root. Backend rules engine and live E2E are done and passing. Next:
> [pick from "Not started yet" above, e.g. "let's do the Flutter table UI"
> or "let's settle the scoring question first"].
