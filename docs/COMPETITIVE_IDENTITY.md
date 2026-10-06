# Competitive Identity, Rankings & Founding Players — design

> Design record for the competitive system. Canonical schema stays
> [DATABASE.md](DATABASE.md); this file explains *why* the competitive tables look the
> way they do and what the service layer does with them. Game-agnostic by
> construction: Draughts is the first consumer, not the subject.

---

## 1. What already exists and is reused (not rebuilt)

Inspection of the repo before any code was written. The competitive system plugs into
these; none of them are rewritten.

| Existing thing | Where | How the competitive system uses it |
|---|---|---|
| `users` (id, username, display_name, avatar_url, is_guest, is_bot, created_at) | `V1`, `V5`, `V7`, `V9` | Identity. `playhuud_number` is added here, not in a side table — it *is* part of identity. `is_bot` and `is_guest` drive ranked eligibility. |
| `game_sessions` (room_id, game_type, started_at, ended_at, rng_seed, config) | `V3` | The durable match row already exists. `match_records` references it 1:1 rather than duplicating config/seed. |
| `game_results` (winning_side, per_player_outcome JSONB) | `V3`, widened in `V26` | Already the game-agnostic outcome shape every module produces. Rating reads `perPlayerOutcome` — no per-game outcome parsing. |
| `game_events` (seq, type, payload, visibility) | `V3` | Already the move/event log the brief asks to retain for later AI analysis and anti-cheat. Nothing new needed. |
| `player_stats` | `V4` | TrueArena-shaped (traitor columns) and only written from `roleRows`, so Draughts/Whot never touch it. Left alone; per-game competitive stats go in a new table rather than bolting game columns onto this one. |
| `WinResult(winningSide, perPlayerOutcome)` | `ta-engine` | The single integration seam. Every module already reports `won`/`lost`/`tied` per player id. |
| `GameOrchestrator.finishGame` | `ta-api/ws` | The one place every game ends, for every game type, tournament or not. The rating hook goes here, alongside the existing stats/coins/stake steps. |
| `championships` + `championship_matches` + `championship_badges` | `V27` | Tournaments already exist. `match_records.championship_id` links a rated match to its tournament; Phase 2 prestige builds on this, no second bracket system. |
| `friends` (ordered pair, status) | `V1` | The friends leaderboard is a join against this — no new social graph. |
| `coins` / `CoinService` | `V12`, `V15` | Precedent for "best-effort side effect at game end that never undoes the result write". Rating follows the same shape. |
| `rooms.game_config` JSONB, `rooms.stake_coins` | `V15`, `V19` | Precedent for per-room host options. `rooms.ranked` joins them. |
| `ReactiveStringRedisTemplate` | already wired (`OtpService`, `RoomLock`) | Leaderboard page + own-rank caching. No new infrastructure. |
| `ta-engine` ("NO Spring", enforced by `NoSpringInEngineTest`) | `ta-engine` | Home for the pure Glicko-2 maths — unit-testable with zero Spring context. |

**Deliberate non-reuse:** `player_stats` is not extended. It is per-`(group, user)` with
TrueArena-specific columns and a `CHECK (traitor_games <= games_played)` domain; per-game
competitive stats are a different grain (`user × game_type`). Two tables, two grains.

---

## 2. Schema changes (`V32__competitive.sql`)

### 2.1 `users` — permanent PlayHuud number

```
users.playhuud_number  BIGINT UNIQUE          -- null only for bot rows
```

Backed by `SEQUENCE playhuud_number_seq` and assigned by a `BEFORE INSERT` trigger when
`NOT is_bot`. This satisfies every requirement at once:

- **unique** — `UNIQUE` constraint;
- **sequential** — a Postgres sequence;
- **server-side** — a trigger; no client or even service code can supply one;
- **immutable** — a `BEFORE UPDATE` trigger forces `OLD.playhuud_number` back;
- **never recycled** — sequences never go backwards, and a deleted account's number is
  simply gone;
- **safe under concurrency** — `nextval` is atomic and non-blocking.

Bots get `NULL` so Cyber Agents can't consume Founding-100 slots.

It is deliberately **not** a `UserRow` field, for the same reason `coins` isn't: the
database assigns and freezes it, so an entity copy would be stale straight after
`save()` (R2DBC returns the entity it sent, not trigger-modified columns). It is read
with `UserRepository.playhuudNumberOf` and served from `/me/competitive`. Guests *do* get a
number: a guest upgrades in place (same `users.id`, see `V7`), so their number survives
verification — which is exactly the incentive we want.

Founding tier is **derived, never stored**: `#1–100` → `FOUNDING_100`, `#101–1000` →
`FOUNDING_1000`, `#1001–10000` → `FOUNDING_10000`. Storing it would be a second source of
truth for a pure function of an immutable column.

### 2.2 `competitive_profiles` — location, one row per user

```
user_id UNIQUE → users, country_code, country_name, region_code, region_name,
city, city_public, location_changes, location_updated_at, location_locked_until
```

`country_code` is ISO 3166-1 alpha-2; `region_code` is a stable `ISO-3166-2`-style slug
(`NG-RI`), not free text, so a leaderboard key can never fork on spelling. Display names
are stored alongside so a profile renders without a lookup table the app would also need.

Anti-manipulation lives in this table rather than in app memory: `location_changes` counts
geographic moves, `location_locked_until` is a cooldown stamp the API enforces.

### 2.3 `player_game_ratings` — the Glicko-2 state, per `(user, game_type)`

```
user_id, game_type, rating, rating_deviation, volatility, peak_rating,
rated_games_played, last_rated_at, provisional, leaderboard_eligible,
country_code, region_code
UNIQUE (user_id, game_type)
```

No universal rating anywhere — `game_type` is in the unique key, so "one rating per game"
is a schema guarantee rather than a convention.

`country_code`/`region_code` are **deliberately denormalised** from
`competitive_profiles` and kept in sync by an `AFTER INSERT OR UPDATE` trigger. This is
the one duplication in the design and it buys the whole leaderboard performance story
(§6): without it, a country leaderboard needs a join and can therefore never use a
partial index on rating.

`provisional` and `leaderboard_eligible` are maintained by the rating service on each
write, not computed per read, so the hot leaderboard query is a pure index scan.

### 2.4 `match_records` + `match_participants` — competitive match history

```
match_records:       game_session_id UNIQUE → game_sessions, game_type, ranked,
                     unranked_reason, championship_id, room_id, winning_side, draw,
                     started_at, completed_at, duration_ms, rated_at
match_participants:  match_id, user_id, outcome, forfeited, disconnected,
                     rating_before, rating_after, rating_delta,
                     rating_deviation_before, rating_deviation_after,
                     opponent_rating_before
                     UNIQUE (match_id, user_id)
```

`game_session_id UNIQUE` is the idempotency key — `finishGame` can run twice for a
tournament room (it already guards `game_results` that way), and an `ON CONFLICT DO
NOTHING` insert that reports zero rows means "already rated, do nothing", so a replay can
never double-apply a rating change.

`unranked_reason` records *why* a match wasn't rated (`vs_agent`, `casual_room`,
`guest_player`, `unrated_game_type`, `too_few_humans`, `self_match`). Unranked matches are
still stored — that is the raw history the brief asks for, and it is what later makes
"this account only ever plays its own alt" detectable.

**RatingHistory is a query, not a table.** `match_participants` joined to `match_records`
ordered by `completed_at` *is* the rating history, with full match context attached. A
separate `rating_history` table would be a copy of columns that already exist here. The
one thing it would add — rating-deviation decay for inactivity, which changes state with
no match — is not in Phase 1; when it arrives it gets an explicit
`unranked_reason='inactivity_decay'`-style synthetic row in these same tables.

### 2.5 `player_game_stats` — per `(user, game_type)` counters

```
games_played, wins, losses, draws, current_win_streak, best_win_streak,
top100_wins, casual_games, last_played_at
```

**Ranked matches only** for W/L/D, streaks and top-100 wins — this is the stat line a
profile and a leaderboard row show, so it must not be inflatable by beating a Cyber Agent
or a casual alt. Casual human-vs-human games still count, separately, in `casual_games`
(the brief's "social/general statistics").

Counters only. `winRate` is derived in the view layer, and **tournament wins are derived
from the existing `championships.champion_id`** rather than kept as a second counter.
Everything here is reconstructable from `match_records` + `match_participants`, which is
the safety net the brief asks for.

### 2.6 `player_achievements` — generic, catalog-in-code

```
user_id, type, game_type (nullable), earned_at, metadata JSONB, display_priority, rarity
UNIQUE NULLS NOT DISTINCT (user_id, type, game_type)
```

The achievement *catalog* (label, icon, priority, rarity) lives in code as an enum, not in
a table: it is versioned with the code that awards it, needs no migration to add, and
can't drift from the awarding logic. The table holds only what is per-player. Founding
badges are **not** stored here — they are a pure function of `playhuud_number`, and
materialising them would mean a backfill row for every account forever.

### 2.7 `rooms.ranked`

```
rooms.ranked BOOLEAN NOT NULL DEFAULT false
```

The host's *request*. The server decides the actual rated-ness at finish time
(`RatedMatchPolicy`, §5) — a room flagged ranked that ends up containing an agent is
recorded unranked with a reason.

---

## 3. Migration & backfill plan

All in `V32`, in order, single transaction (Flyway default):

1. `CREATE SEQUENCE playhuud_number_seq`.
2. `ALTER TABLE users ADD COLUMN playhuud_number BIGINT` (nullable, no constraint yet).
3. **Deterministic backfill** of existing non-bot accounts:
   ```sql
   WITH ordered AS (
     SELECT id, row_number() OVER (ORDER BY created_at, id) AS n
     FROM users WHERE NOT is_bot
   )
   UPDATE users u SET playhuud_number = o.n FROM ordered o WHERE u.id = o.id;
   ```
   `ORDER BY created_at, id` — `id` breaks ties so the result is reproducible if the
   migration is ever re-run against a restored snapshot. Earliest account becomes
   PlayHuud #000001, which is the historically honest answer and makes the existing dev/
   early accounts genuinely Founding 100.
4. `setval` the sequence past the highest backfilled number.
5. `ADD CONSTRAINT users_playhuud_number_key UNIQUE`, then install the assign/immutability
   triggers. Order matters: the backfill must land before the immutability trigger exists,
   or it would be silently reverted.
6. Create the competitive tables, indexes, and the location-sync trigger.
7. Seed `player_game_ratings`/`player_game_stats`? **No.** Rows are created lazily on
   first rated match. A pre-seeded 1500 for every account would put thousands of accounts
   that have never played Draughts onto the Draughts leaderboard at identical ratings.

Rolling-deploy safety: every column added is nullable or has a default, and the old code
path never writes these tables, so an old backend instance running against the new schema
keeps working unchanged. The migration is additive only — no column is dropped or
retyped, so a rollback to the previous jar needs no down-migration.

---

## 4. Rating service design (Glicko-2)

`ta-engine` → `app.truearena.engine.rating`:

- **`Glicko2`** — the published Glickman algorithm, pure static functions, no Spring, no
  I/O. System constant τ = 0.5. Operates on the internal Glicko-2 scale (µ, φ) and
  converts back to the familiar 1500/350 scale at the boundary. New accounts start
  `1500 / RD 350 / vol 0.06` — the maximal-uncertainty start the brief asks for, which is
  what lets a genuinely strong player climb in a handful of games.
- **`RatingSnapshot(rating, deviation, volatility)`** — the immutable state triple.
- **`MatchOutcome(opponent, score)`** — `score` is 1 / 0.5 / 0.

Key design decision: **a match is a rating period of one**, with multi-player games
expanded pairwise. A 4-player Whot game becomes, for each player, three
`MatchOutcome`s (one per opponent, scored 1/0.5/0 from `perPlayerOutcome`), all evaluated
in a single Glicko-2 update. This is the standard multi-player generalisation and it means
Draughts (1 opponent) and Ludo (3 opponents) use literally the same code path — which is
the whole point of making this game-agnostic.

Opponent quality falls out of the maths rather than being special-cased: Glicko-2's
expected-score term `E(µ, µ_j, φ_j)` is what makes beating a stronger opponent worth more
and losing to a weaker one cost more, and the `φ`-weighting means a result against an
uncertain opponent moves you less.

`ta-api` → `app.truearena.api.competitive`:

- **`RatingService`** — load state → compute → persist ratings, stats, match rows,
  achievements, in one reactive chain.
- **`RatedMatchPolicy`** — the pure eligibility decision (§5).
- **`CompetitiveProfileService`** — PlayHuud number/founding tier, location with change
  control.
- **`LeaderboardService`** — scoped queries + cache (§6).
- **`AchievementService`** — evaluates the catalog against a finished match.

**Server authoritative, structurally.** Clients have no endpoint that accepts a rating,
a delta, a rank, or an outcome. The only input to the whole system is a `WinResult`
produced by a `GameModule` running inside the orchestrator, from moves the engine itself
validated. There is nothing for a client to forge.

---

## 5. Match → rating update flow

```
GameModule.checkWinCondition  →  WinResult{winningSide, perPlayerOutcome}
        │
GameOrchestrator.finishGame
  saveResult → flushEvents → endSession → endRoom → stats → coins → stake → tournament
        │
        └── competitive.recordMatch(session, gameType, room, outcome, startedAt)   ← new, last
                │
                1. RatedMatchPolicy.decide(gameType, participants, room)
                │     → RANKED, or UNRANKED + reason
                2. INSERT match_records ... ON CONFLICT (game_session_id) DO NOTHING
                │     → 0 rows ⇒ already recorded, stop (idempotent replay)
                3. load player_game_ratings for every human participant (lazily created)
                4. Glicko2.update(each player, pairwise opponents)   ← pure
                5. INSERT match_participants with before/after/delta per player
                6. UPDATE player_game_ratings (rating, RD, vol, peak, count, provisional,
                │   leaderboard_eligible)
                7. UPDATE player_game_stats (W/L/D, streaks, last_played_at)
                8. AchievementService.evaluate(...)
                9. invalidate cached leaderboard pages for the touched scopes
```

Placed **last** in `finishGame` and wrapped in `onErrorResume`, matching the existing
`updateStats`/`awardCoins` precedent: a rating failure must never cost a player their
coins, their stake payout, or their tournament advancement. The match row is written
before any rating maths runs, so a crash mid-update leaves a recorded match that a repair
job can re-rate rather than a silently lost game.

Forfeits are read from `championship_actions` (the only durable forfeit log today), and
`disconnected` means "not connected when the game ended" (`RoomRuntime.connectedUserIds`).

Steps 2–7 run in one `TransactionalOperator` so a player's rating and the
`match_participants` row recording it can never disagree.

Casual matches stop after step 2 (recorded, `ranked=false`) and step 7's non-ranked
counters — no rating touched, no leaderboard effect. That is the ranked/casual separation
the brief asks for, and it costs one boolean.

---

## 6. Leaderboard query & caching design

Three scopes, one query shape, three partial indexes:

```sql
CREATE INDEX player_game_ratings_global_idx ON player_game_ratings (game_type, rating DESC)
  WHERE leaderboard_eligible;
CREATE INDEX player_game_ratings_country_idx ON player_game_ratings (game_type, country_code, rating DESC)
  WHERE leaderboard_eligible;
CREATE INDEX player_game_ratings_region_idx ON player_game_ratings (game_type, country_code, region_code, rating DESC)
  WHERE leaderboard_eligible;
```

Because country/region are denormalised onto the ratings row and eligibility is a stored
boolean, **a leaderboard page is an index scan with a LIMIT** — the planner never sorts
and never touches an ineligible or provisional row. The join to `users` for name/avatar
happens on at most `limit` rows.

"My rank" is `COUNT(*)` of eligible rows that sort ahead of you. The query carries a
redundant `rating >= mine` bound: without it the tiebreak `OR` hides the range from the
planner and it degrades to a full scan of the board (seen in `EXPLAIN` on 20k rows);
with it, the cost scales with the number of players *ahead* of you, not the board size — no leaderboard materialisation, nothing recomputed from scratch, exactly
what §24 of the brief forbids. At six figures of rows this is single-digit milliseconds;
it is cached in Redis for 60 s per `(user, game, scope)` anyway, because a profile view
asks for three ranks at once.

Leaderboard *pages* are cached in Redis for 60 s keyed
`lb:{gameType}:v{version}:{scope}:{scopeKey}:{offset}`; a rated match bumps the game's
version (`INCR lb:ver:{gameType}`) rather than hunting down keys, and orphaned versions
expire on their TTL. Ties break on `rated_games_played DESC, user_id` — both on the
ratings row itself, so rank counts stay inside the index — so pagination is stable — without a deterministic tiebreak, two players on 1842 can swap
between page requests and a player can appear twice or vanish.

Friends scope can't use those indexes (it is bounded by the friend list, not by rating),
so it is a join against `friends` with no eligibility filter — a friends board should show
your friends even when they are provisional, which is also why it is uncached.

Escalation path, deliberately not built yet: when a single-scope count stops being cheap,
the fix is a periodically-refreshed `leaderboard_ranks` table keyed
`(game_type, scope, scope_key, user_id)`. Nothing above needs to change to adopt it —
`LeaderboardService` is the only caller.

---

## 7. API changes

New, all under `/api/v1`:

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/me/competitive` | Own full competitive profile: PlayHuud number, founding tier, location, per-game record with global/country/region ranks, achievements. |
| `PATCH` | `/me/competitive` | Set country / region / city. Enforces the change-control rules; `409` with a human message when locked. |
| `GET` | `/players/{username}/competitive` | Public competitive profile (privacy-filtered, §25 of the brief). |
| `GET` | `/leaderboards/{gameType}` | `?scope=global\|country\|region\|friends&limit&offset`. Includes the caller's own row/rank so the app can show "you are #127" under the page. |
| `GET` | `/me/matches` | Rated + casual match history, `?gameType=&limit=`, with per-match rating delta. |

Also: `GET /competitive/games` (rated game types), `GET /competitive/locations` and
`GET /competitive/locations/{country}` (the country/region catalog, served so the app
holds no second copy), and `GET /players/{username}/matches`.

Changed: `RoomView` gains `ranked`; `CreateRoomRequest` gains optional `ranked`. Both
additive — older app builds ignore/omit them and get today's behaviour (casual).
`UserView` is deliberately unchanged: the PlayHuud number lives on `/me/competitive`
(see §2.1).

Nothing accepts a rating, delta, rank, or outcome from a client. `POST /rooms` gains an
optional `ranked` boolean, which is a *request*, not a determination.

---

## 8. Mobile UI changes

- **`competitive_setup_screen.dart`** — the post-registration profile step. Country
  (searchable), region (populated per country), optional city. Skippable: a "Skip for now"
  path leaves the player fully able to play and appear on global rankings, per the brief's
  friction rule.
- **`profile_screen.dart`** — a competitive header (PlayHuud number + founding badge)
  above the existing avatar block, and a `COMPETITIVE RECORD` section listing each game
  with rating and country rank. Existing wallet/appearance/championship sections stay
  untouched.
- **`competitive_profile_screen.dart`** — per-game detail: rating, peak, the three ranks
  (with "Complete profile" affordances where location is missing), W/L/D, win rate,
  streaks, recent rated matches with deltas.
- **`leaderboard_screen.dart`** — scope tabs (Global / Country / State / Friends), the
  caller's own row pinned, founding badges inline.
- **`models.dart`** — `CompetitiveProfile`, `GameRating`, `LeaderboardEntry`,
  `FoundingTier`, and the `#000127` formatter.

Everything uses the existing `NeonCard` / `NeonButton` / `Avatar` / `context.neon`
vocabulary — the status feel the brief asks for comes from typography and hierarchy
(rank huge, label small, badge gold) rather than a new design system.

---

### 8.1 Player cards and profile visibility

Every profile — your own, a friend's, anyone opened from a leaderboard — shows a
swipeable set of FUT-style shield cards (`player_card.dart`): **Overall** first, then one
card per rated game, each in its own livery (Draft teal/yellow, Whot black/lime, …). The
carousel tilts and drops the neighbouring cards so the row sits on an arc, and the
focused card glints once as it lands. A game you haven't played still gets its card,
blank, so the set is always complete.

The Overall card is **not** a blended rating — there is no universal rating by design.
Its corner shows your best game rating labelled with that game (`1842 DRA`); the rest is
career totals (games, win %, titles, best streak, badges, best national rank).

Tapping a friend now opens their profile; their Status stays one tap away in the app bar.

Profiles are **public by default** (`competitive_profiles.profile_public`). Turning it off
leaves only name, avatar, PlayHuud number and founding tier visible to others (the
response carries `restricted: true`), and `/players/{username}/matches` returns 403.
Leaderboards are unaffected — a rank is a fact about the board, not the profile.

## 9. Tests

Runnable without Docker (plain JUnit):

- `Glicko2Test` — verifies against the worked example in Glickman's own paper
  (1500/200/0.06 vs three opponents → µ′ 1464.06, φ′ 151.52). A rating engine that is not
  checked against the reference numbers is just plausible-looking arithmetic.
- Monotonicity properties: beating a stronger opponent gains more than beating a weaker
  one; losing to a weaker one costs more than losing to a stronger one; a provisional
  opponent moves you less. These are the brief's §6 requirements stated as assertions.
- `PairwiseOutcomesTest` — `perPlayerOutcome` → per-player opponent lists, for 2-, 3- and
  4-player games, including `tied`.
- `RatedMatchPolicyTest` — agent present, guest present, casual room, single human,
  unrated game type, duplicate user.
- `FoundingTierTest` / `PlayhuudNumberFormatTest` — boundaries at 100/101/1000/1001/10000/
  10001 and the `#000127` format.
- `AchievementRulesTest` — first win, 10/100/1000 wins, 10/25 streaks, top-100 victory.

Needs Postgres (`@Tag("integration")`, run under `./mvnw verify`):

- PlayHuud number: concurrent registration assigns distinct sequential numbers; bots get
  none; an `UPDATE` attempt leaves the number unchanged.
- Backfill determinism on a seeded `users` table.
- Idempotency: `recordMatch` twice for one session applies the rating once.
- Leaderboard scoping/eligibility/tiebreak, and that `EXPLAIN` on the global page uses the
  partial index.

Flutter (`flutter test`):

- `competitive_profile_test.dart` — model parsing, founding-tier formatting, the
  "Complete profile to unlock" state when country is absent.
- `leaderboard_test.dart` — scope tabs render, own row pins.

`CompetitiveRatingIT` (in `ta-app`, 15 tests) covers all of the above. It uses the same
Testcontainers rig as `ChampionshipServiceIT`, and can alternatively target an existing
**empty** Postgres/Redis via `-Dit.r2dbc.url=… -Dit.jdbc.url=… -Dit.db.user=… -Dit.db.password=…
-Dit.redis.port=… -Dit.redis.database=…` for machines where Testcontainers can't start
containers (see the class doc for the full command).

---

## 10. Rollout & backward-compatibility risks

| Risk | Severity | Mitigation |
|---|---|---|
| Backfill order is wrong and someone's Founding 100 is someone else's | high (irreversible in perception) | Deterministic `ORDER BY created_at, id`; the backfill is verified against the row count before the `UNIQUE` constraint goes on, and the whole migration is one transaction. |
| Immutability trigger reverts a legitimate `users` update | medium | The trigger forces `OLD.playhuud_number` only; every other column updates normally. `UserRow` carries the field so R2DBC round-trips it unchanged anyway — the trigger is a backstop, not the mechanism. |
| Rating applied twice after a tournament-room replay | high (rating integrity) | `match_records.game_session_id UNIQUE` + `ON CONFLICT DO NOTHING`; zero affected rows short-circuits the whole update. |
| Early leaderboards look empty / a one-win account appears as national #1 | high (credibility) | Provisional state + `leaderboard_eligible` gate at 10 rated games, configurable. An empty board is honest; a fake #1 is not. |
| Denormalised `country_code` drifts from `competitive_profiles` | medium | A database trigger, not service code, is the sync mechanism — it cannot be bypassed by a new write path. |
| Location switching to farm an easier board | medium | `location_changes` + `location_locked_until`: first set is free, first correction free, subsequent country changes cooldown 30 days; every change is counted and timestamped so a reviewer can see the pattern. |
| Rating failure breaks match completion | high | `recordMatch` runs last in `finishGame` under `onErrorResume`, like coins and stats. |
| Old app builds break on new `UserView` fields | low | Additive nullable JSON fields; Dart model ignores unknown keys. |
| Rating inflation/deflation across the population | low now, real later | Glicko-2 is zero-sum per match; the fixed 1500 start means a growing population doesn't inflate. Worth a periodic distribution check once volume exists. |
| `ranked` default | low | Defaults to `false`. Nothing silently becomes rated; a room is rated only when asked for *and* the policy agrees. |
