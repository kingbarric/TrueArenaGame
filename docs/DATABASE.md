# TrueArena — Database schema (canonical)

> **Source of truth.** The executable truth is `backend/ta-persistence/src/main/resources/db/migration/`.
> This file describes what those migrations build; `ARCHITECTURE.md` and `GAME_CONFIG.md`
> point here rather than repeating it. Keep this in step with every new migration.

Postgres 16. Conventions in every table:

- surrogate `id UUID PRIMARY KEY DEFAULT gen_random_uuid()` — natural keys are `UNIQUE`
  constraints, not the PK (Spring Data R2DBC has no composite-key support);
- every enum-like `TEXT` column carries a `CHECK` for its domain (listed below);
- timestamps are `TIMESTAMPTZ DEFAULT now()`;
- `ON DELETE CASCADE` down ownership edges; `ON DELETE SET NULL` where the child outlives
  the parent (`rooms.group_id`).

Live per-round state (current votes, un-flushed events, in-play roles) lives in **Redis**
during a game; these tables are the durable record written at/near session end.

---

## V1 — core (`V1__core.sql`)

### `users`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| display_name | text not null | |
| avatar_url | text | nullable — a bare emoji for a preset icon, or a URL once photo upload has storage |
| phone | text **unique**, nullable | one of two auth identities (phone + OTP) |
| email | text **unique**, nullable | the other auth identity (email + OTP) |
| username | text not null **unique** | a real handle; auto-generated at signup if not chosen, editable via `PATCH /me` |
| created_at | timestamptz | |
| | | **CHECK** phone IS NOT NULL OR email IS NOT NULL (V5) |

### `groups`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| name | text not null | e.g. "Friday Crew" |
| created_by | uuid not null → users.id | |
| created_at | timestamptz | |

### `group_members`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| group_id | uuid not null → groups.id (cascade) | |
| user_id | uuid not null → users.id (cascade) | |
| role | text not null default `member` | **CHECK** `owner` \| `member` |
| joined_at | timestamptz | |
| | | **unique** (group_id, user_id) |

### `friends`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| low_user_id | uuid not null → users.id (cascade) | ordered pair — see checks |
| high_user_id | uuid not null → users.id (cascade) | |
| status | text not null | **CHECK** `pending` \| `accepted` |
| requested_by | uuid not null → users.id | **CHECK** ∈ (low_user_id, high_user_id) |
| created_at | timestamptz | |
| | | **unique** (low_user_id, high_user_id) · **CHECK** low_user_id < high_user_id |

---

## V2 — rooms (`V2__rooms.sql`)

### `rooms`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| code | text not null **unique** | 6-char join code |
| group_id | uuid → groups.id (**set null**) | null = ad-hoc / web-funnel room |
| host_id | uuid not null → users.id | migrates on host disconnect |
| status | text not null default `lobby` | **CHECK** `lobby` \| `in_game` \| `ended` |
| game_type | text not null default `truearena` | the `GameModule` id. **CHECK** `truearena` \| `wordbluff` \| `draughts` \| `goosi` \| `whot` — each new game widens it in its own migration (V6, V8, V10, V21), so adding one to `RoomService.GAME_TYPES` alone is not enough |
| stake_coins | bigint not null default 0 | coins each player puts up; **CHECK** ≥ 0. Refunded if the lobby is abandoned |
| game_config | text | host-chosen rules for this room as JSON, read at start by the game's module (`draughtsConfigFrom` / `goosiConfigFrom` / `whotConfigFrom` in `GameOrchestrator`); null, blank or unreadable = that game's defaults |
| created_at | timestamptz | |
| | | index (group_id) |

### `room_members`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| room_id | uuid not null → rooms.id (cascade) | |
| user_id | uuid not null → users.id (cascade) | |
| nickname | text | guest / display override |
| connection_status | text not null default `connected` | **CHECK** `connected` \| `disconnected` |
| ready_state | boolean not null default false | lobby ready-check |
| joined_at | timestamptz | |
| | | **unique** (room_id, user_id) |

---

## V3 — the game (`V3__game.sql`) · config model: [GAME_CONFIG.md](GAME_CONFIG.md)

### `game_config_preset`
The 5 shipped modes (`scope='builtin'`, rewritten from code on every boot by `PresetSeeder`)
plus group- and user-authored custom games.

| column | type | notes |
|---|---|---|
| id | uuid pk | |
| scope | text not null | **CHECK** `builtin` \| `group` \| `user` |
| owner_group_id | uuid → groups.id (cascade) | set iff scope = `group` |
| owner_user_id | uuid → users.id (cascade) | set iff scope = `user` |
| slug | text | set iff scope = `builtin` (`blood_moon`, …) |
| name | text not null | |
| description | text | |
| tag | text | e.g. `Default` |
| config | jsonb not null | a full `GameConfig` (GAME_CONFIG.md §3) |
| catalog_version | int not null | |
| created_at | timestamptz | |
| | | **unique** (scope, slug) · partial **unique** (owner_user_id, name) where user · partial **unique** (owner_group_id, name) where group |
| | | **CHECK** owner columns + slug line up with scope (exactly one owner for group/user; none + slug for builtin) |

### `game_sessions`
One live instance of a game in a room.

| column | type | notes |
|---|---|---|
| id | uuid pk | |
| room_id | uuid not null → rooms.id (cascade) | index |
| game_type | text not null default `truearena` | the `GameModule` id |
| config | jsonb not null | the resolved `GameConfig` this session runs |
| config_preset_id | uuid → game_config_preset.id | the preset it started from (nullable) |
| catalog_version | int not null | catalog the session replays under |
| rng_seed | bigint not null | deterministic replay |
| phase | text not null default `Lobby` | engine-defined; **not** constrained |
| round | int not null default 0 | **CHECK** ≥ 0 |
| phase_ends_at | timestamptz | when the current timed phase elapses; null = untimed |
| started_at | timestamptz | |
| ended_at | timestamptz | null while live |

### `roles`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| game_session_id | uuid not null → game_sessions.id (cascade) | |
| user_id | uuid not null → users.id | |
| role_type | text not null | **CHECK** `traitor` \| `faithful` \| `recruited_traitor` |
| | | **unique** (game_session_id, user_id) |

### `game_events`
Append-only log, flushed from the Redis stream.

| column | type | notes |
|---|---|---|
| id | uuid pk | |
| game_session_id | uuid not null → game_sessions.id (cascade) | |
| seq | bigint not null | **CHECK** ≥ 1 |
| type | text not null | e.g. `PLAYER_ELIMINATED` |
| payload | jsonb not null | |
| visibility_scope | text not null | **CHECK** `public` \| `player` \| `role` |
| visibility_key | text | player id / role for scoped events. **CHECK** `(scope = public) = (key IS NULL)` |
| created_at | timestamptz | |
| | | **unique** (game_session_id, seq) |

### `votes`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| game_session_id | uuid not null → game_sessions.id (cascade) | |
| round | int not null | **CHECK** ≥ 1 |
| voter_id | uuid not null → users.id | |
| target_id | uuid not null → users.id | **CHECK** voter_id ≠ target_id |
| | | **unique** (game_session_id, round, voter_id) — one locked vote per round |

### `game_results`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| game_session_id | uuid not null **unique** → game_sessions.id (cascade) | |
| winning_side | text not null | **CHECK** `faithful` \| `traitors` |
| per_player_outcome | jsonb not null | `{ userId: "won" \| "lost" }` |
| created_at | timestamptz | |

---

## V4 — stats (`V4__stats.sql`)

### `player_stats`
One row per `(group_id, user_id)`; a **`group_id IS NULL`** row is that user's **lifetime
rollup** (ad-hoc / web-funnel games touch only the lifetime row). Counts only — rates
(traitor win-rate, etc.) are derived in queries.

| column | type | notes |
|---|---|---|
| id | uuid pk | |
| group_id | uuid → groups.id (cascade) | null = lifetime rollup |
| user_id | uuid not null → users.id (cascade) | index |
| games_played | int not null default 0 | |
| wins | int not null default 0 | **CHECK** ≤ games_played |
| traitor_games | int not null default 0 | **CHECK** ≤ games_played |
| traitor_wins | int not null default 0 | **CHECK** ≤ traitor_games |
| times_first_accused | int not null default 0 | first player voted for in a round |
| current_win_streak | int not null default 0 | **CHECK** ≤ longest_win_streak |
| longest_win_streak | int not null default 0 | |
| updated_at | timestamptz | |
| | | **unique NULLS NOT DISTINCT** (group_id, user_id) |

---

## V5 — profile (`V5__profile.sql`)

Makes `phone` optional and adds `email` as the other registration path (`users` table
above already reflects the final shape); adds the required-unique `username`, backfilled
for pre-existing rows as `player_<first 8 of id>`. No new tables — this migration only
`ALTER`s `users`.

---

> V6–V31 are not yet written up here — the migration files are the source of truth for them.

## V32 — competitive identity (`V32__competitive.sql`) · design: [COMPETITIVE_IDENTITY.md](COMPETITIVE_IDENTITY.md)

### `users` (added)
| column | type | notes |
|---|---|---|
| playhuud_number | bigint **unique**, nullable | permanent sequential PlayHuud number. Assigned by `BEFORE INSERT` trigger from `playhuud_number_seq` (null for bots); frozen by a `BEFORE UPDATE` trigger; never recycled. Existing humans backfilled `ORDER BY created_at, id`. Not on `UserRow` — read via `UserRepository.playhuudNumberOf` (same reason as `coins`). |

### `rooms` (added)
| column | type | notes |
|---|---|---|
| ranked | boolean not null default false | the host's *request* for a rated match; `RatedMatchPolicy` decides at game end |

### `competitive_profiles`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| user_id | uuid not null **unique** → users.id, cascade | |
| country_code | text | ISO 3166-1 alpha-2, **CHECK** `^[A-Z]{2}$` |
| country_name / region_name | text | display copies |
| region_code | text | ISO 3166-2 style (`NG-RI`), or `CC-SLUG` for uncatalogued countries; **CHECK** requires country |
| city | text | optional, private unless `city_public` |
| city_public | boolean not null default false | |
| location_changes | int not null default 0 | changes after the first set; drives the cooldown / support-review rule |
| location_updated_at / location_locked_until | timestamptz | |
| created_at / updated_at | timestamptz | |

Trigger `competitive_profiles_sync_rating_location` copies country/region onto every `player_game_ratings` row for the user.

### `player_game_ratings`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| user_id | uuid not null → users.id, cascade | **unique** (user_id, game_type) — one rating per game, no universal rating |
| game_type | text not null | |
| rating / rating_deviation / volatility | double not null | Glicko-2 state, defaults 1500 / 350 / 0.06 |
| peak_rating | double not null | |
| rated_games_played | int not null | |
| provisional / leaderboard_eligible | boolean not null | maintained by `RatingService`; boards read only eligible rows |
| country_code / region_code | text | **trigger-maintained** copy of the profile location (denormalised for partial-index boards) |
| last_rated_at / created_at | timestamptz | |

Partial indexes (all `WHERE leaderboard_eligible`): `(game_type, rating DESC, rated_games_played DESC, user_id)`, the same prefixed with `country_code`, and with `country_code, region_code`.

### `player_game_stats`
Per `(user_id, game_type)`, **ranked matches only**: `games_played, wins, losses, draws` (**CHECK** they sum), `current_win_streak, best_win_streak, top100_wins`, plus `casual_games` (human-vs-human unrated games), `last_played_at`, `updated_at`.

### `match_records`
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| game_session_id | uuid **unique** → game_sessions.id, set null | the idempotency key — a replayed `finishGame` can't rate twice |
| room_id / championship_id | uuid, set null | |
| game_type | text not null | |
| ranked | boolean not null | **CHECK** `ranked = (unranked_reason IS NULL)` |
| unranked_reason | text | `unrated_game_type`, `casual_room`, `vs_agent`, `guest_player`, `too_few_humans`, `repeat_opponent` |
| winning_side / draw / player_count | | |
| started_at / completed_at / duration_ms / rated_at | | |

### `match_participants`
Per `(match_id, user_id)` (**unique**): `outcome` (`won`/`lost`/`tied`), `forfeited`, `disconnected`, and — only on a rated match — `rating_before, rating_after, rating_delta, deviation_before, deviation_after, opponent_rating_before` (mean, for multi-player). This **is** the rating history; there is no separate history table.

### `player_achievements`
`user_id, type, game_type (nullable), earned_at, metadata jsonb, display_priority, rarity` — **unique NULLS NOT DISTINCT** (user_id, type, game_type). Catalog lives in code (`AchievementType`); founding badges are derived from `playhuud_number`, never stored.

## V34 — profile visibility (`V34__profile_visibility.sql`)

Adds `competitive_profiles.profile_public BOOLEAN NOT NULL DEFAULT true` — public by
default; when false, other players see identity only. A separate migration because V32
was already applied in production before this column existed.

---

## Not yet migrated (tracked)

- **Guest identity** (`PROJECT_PLAN.md` 2.4): a `guest_session` (or a `users` flag)
  keyed by device id, purged after one game unless a phone/email is claimed. Needs a
  migration when the guest endpoint is built.
- **Reconnection log offset / snapshot** for `game_sessions` if the Redis stream isn't
  enough for crash recovery (Phase 4).
