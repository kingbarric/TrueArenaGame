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
| avatar_url | text | nullable |
| phone | text not null **unique** | the auth identity (phone + OTP) |
| created_at | timestamptz | |

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

## Not yet migrated (tracked)

- **Guest identity** (`PROJECT_PLAN.md` 2.4): a `guest_session` (or a `users` flag)
  keyed by device id, purged after one game unless a phone/email is claimed. Needs a
  migration when the guest endpoint is built.
- **Reconnection log offset / snapshot** for `game_sessions` if the Redis stream isn't
  enough for crash recovery (Phase 4).
