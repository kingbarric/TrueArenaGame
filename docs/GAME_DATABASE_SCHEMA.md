# Traitors and Faithful Database Schema Draft

This is a PostgreSQL 16 design for the Traitors and Faithful game module. It extends the existing `users`, `groups`, `rooms`, and `room_members` tables without changing them. It keeps private roles, traitor actions, and unrevealed votes separate from public game history.

## Design decisions

- A `game_session` is one complete play-through in a room. A room may host many sessions.
- Game mode rules are stored as versioned JSONB snapshots. A running game never changes because a preset was later edited.
- `session_roles`, private action targets, and unrevealed votes are secret data. They must never be returned from broadcast queries or written into public events.
- `game_events` is append-only and is the authoritative public/private timeline. Operational tables make current-state reads and result reporting fast.
- `rounds` represent a night-to-elimination cycle. A poison can resolve in a later round but retains the round in which it was created.
- Every player in a game gets a `session_player` row, even after elimination or disconnection.

## Core enums

Use PostgreSQL `TEXT` columns with `CHECK` constraints rather than database enums. That keeps rule expansion and migration rollout simple.

| Field | Values |
|---|---|
| game session status | `lobby`, `role_reveal`, `night`, `discussion`, `vote`, `vote_review`, `elimination`, `final_fire`, `results`, `cancelled` |
| player state | `alive`, `eliminated`, `spectating`, `left` |
| role | `faithful`, `traitor` |
| elimination source | `murder`, `poison`, `vote`, `random_tie`, `host_decision`, `final_fire`, `left` |
| secret action type | `murder`, `direct_poison`, `claim_shield`, `recruit`, `skip_murder`, `false_reveal` |
| item kind | `true_shield`, `poisoned_shield`, `immunity_coin` |
| event audience | `public`, `host`, `player`, `traitor` |

## Proposed Flyway migration

Save the following as `backend/ta-persistence/src/main/resources/db/migration/V3__gameplay.sql` when implementation begins. It deliberately follows the repository convention of surrogate UUID primary keys.

```sql
CREATE TABLE game_rule_presets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id   UUID REFERENCES users (id) ON DELETE CASCADE,
    group_id        UUID REFERENCES groups (id) ON DELETE CASCADE,
    slug            TEXT NOT NULL,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL,
    min_players     SMALLINT NOT NULL CHECK (min_players BETWEEN 4 AND 20),
    max_players     SMALLINT NOT NULL CHECK (max_players BETWEEN min_players AND 20),
    is_system       BOOLEAN NOT NULL DEFAULT false,
    rules           JSONB NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((is_system AND owner_user_id IS NULL AND group_id IS NULL)
        OR (NOT is_system AND owner_user_id IS NOT NULL))
);

CREATE UNIQUE INDEX game_rule_presets_system_slug_uq
    ON game_rule_presets (slug) WHERE is_system;
CREATE UNIQUE INDEX game_rule_presets_owner_slug_uq
    ON game_rule_presets (owner_user_id, group_id, slug) WHERE NOT is_system;

CREATE TABLE game_sessions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id             UUID NOT NULL REFERENCES rooms (id) ON DELETE RESTRICT,
    preset_id           UUID REFERENCES game_rule_presets (id) ON DELETE SET NULL,
    preset_name         TEXT NOT NULL,
    rules_snapshot      JSONB NOT NULL,
    host_id             UUID NOT NULL REFERENCES users (id),
    rng_seed            BIGINT NOT NULL,
    player_count        SMALLINT NOT NULL CHECK (player_count BETWEEN 4 AND 20),
    admin_override      BOOLEAN NOT NULL DEFAULT false,
    status              TEXT NOT NULL DEFAULT 'lobby'
                        CHECK (status IN ('lobby','role_reveal','night','discussion','vote',
                                          'vote_review','elimination','final_fire','results','cancelled')),
    current_round       SMALLINT NOT NULL DEFAULT 0 CHECK (current_round >= 0),
    phase_ends_at       TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    ended_at            TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX game_sessions_room_created_idx ON game_sessions (room_id, created_at DESC);

CREATE TABLE session_players (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_session_id     UUID NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    room_member_id      UUID REFERENCES room_members (id) ON DELETE SET NULL,
    seat_number         SMALLINT NOT NULL CHECK (seat_number > 0),
    display_name        TEXT NOT NULL,
    state               TEXT NOT NULL DEFAULT 'alive'
                        CHECK (state IN ('alive','eliminated','spectating','left')),
    eliminated_at       TIMESTAMPTZ,
    elimination_source  TEXT CHECK (elimination_source IN
                        ('murder','poison','vote','random_tie','host_decision','final_fire','left')),
    eliminated_round    SMALLINT,
    joined_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (game_session_id, user_id),
    UNIQUE (game_session_id, seat_number)
);
CREATE INDEX session_players_alive_idx ON session_players (game_session_id, state);

-- Access only through player-scoped or host-scoped queries until the role is revealed.
CREATE TABLE session_roles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_session_id     UUID NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    session_player_id   UUID NOT NULL REFERENCES session_players (id) ON DELETE CASCADE,
    initial_role        TEXT NOT NULL CHECK (initial_role IN ('faithful','traitor')),
    current_role        TEXT NOT NULL CHECK (current_role IN ('faithful','traitor')),
    assigned_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    recruited_at        TIMESTAMPTZ,
    recruited_round     SMALLINT,
    revealed_at         TIMESTAMPTZ,
    revealed_reason     TEXT,
    UNIQUE (game_session_id, session_player_id)
);
CREATE INDEX session_roles_active_traitor_idx
    ON session_roles (game_session_id, current_role) WHERE revealed_at IS NULL;

CREATE TABLE game_rounds (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_session_id     UUID NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    round_number        SMALLINT NOT NULL CHECK (round_number > 0),
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    night_ended_at      TIMESTAMPTZ,
    discussion_ended_at TIMESTAMPTZ,
    vote_ended_at       TIMESTAMPTZ,
    ended_at            TIMESTAMPTZ,
    UNIQUE (game_session_id, round_number)
);

-- target_session_player_id and private_payload are never public.
CREATE TABLE secret_actions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_session_id     UUID NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    game_round_id       UUID REFERENCES game_rounds (id) ON DELETE CASCADE,
    action_type         TEXT NOT NULL CHECK (action_type IN
                        ('murder','direct_poison','claim_shield','recruit','skip_murder','false_reveal')),
    actor_session_player_id UUID REFERENCES session_players (id) ON DELETE SET NULL,
    target_session_player_id UUID REFERENCES session_players (id) ON DELETE SET NULL,
    private_payload     JSONB NOT NULL DEFAULT '{}'::jsonb,
    status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','confirmed','resolved','cancelled')),
    resolved_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX secret_actions_session_round_idx ON secret_actions (game_session_id, game_round_id);

CREATE TABLE session_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_session_id     UUID NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    created_round       SMALLINT NOT NULL CHECK (created_round > 0),
    item_kind           TEXT NOT NULL CHECK (item_kind IN ('true_shield','poisoned_shield','immunity_coin')),
    holder_session_player_id UUID REFERENCES session_players (id) ON DELETE SET NULL,
    visibility          TEXT NOT NULL DEFAULT 'public_claim'
                        CHECK (visibility IN ('secret','public_claim','public_holder')),
    claimed_at          TIMESTAMPTZ,
    expires_after_round SMALLINT,
    consumed_at         TIMESTAMPTZ,
    resolution_payload  JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Votes remain hidden while a Veiled Endgame or sequential reveal is active.
CREATE TABLE votes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_session_id     UUID NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    game_round_id       UUID NOT NULL REFERENCES game_rounds (id) ON DELETE CASCADE,
    voter_session_player_id UUID NOT NULL REFERENCES session_players (id) ON DELETE CASCADE,
    target_session_player_id UUID REFERENCES session_players (id) ON DELETE SET NULL,
    status              TEXT NOT NULL DEFAULT 'locked'
                        CHECK (status IN ('locked','abstained','host_assigned','invalidated')),
    locked_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    revealed_at         TIMESTAMPTZ,
    UNIQUE (game_round_id, voter_session_player_id)
);
CREATE INDEX votes_round_target_idx ON votes (game_round_id, target_session_player_id);

-- This table contains no role or target data unless the audience permits it.
CREATE TABLE game_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_session_id     UUID NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    seq                 BIGINT NOT NULL,
    event_type          TEXT NOT NULL,
    audience            TEXT NOT NULL CHECK (audience IN ('public','host','player','traitor')),
    audience_player_id  UUID REFERENCES session_players (id) ON DELETE CASCADE,
    payload             JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (game_session_id, seq),
    CHECK ((audience = 'player' AND audience_player_id IS NOT NULL)
        OR (audience <> 'player' AND audience_player_id IS NULL))
);
CREATE INDEX game_events_session_seq_idx ON game_events (game_session_id, seq);

CREATE TABLE game_results (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_session_id     UUID NOT NULL UNIQUE REFERENCES game_sessions (id) ON DELETE CASCADE,
    winning_side        TEXT NOT NULL CHECK (winning_side IN ('faithful','traitor')),
    win_reason          TEXT NOT NULL CHECK (win_reason IN
                        ('all_traitors_eliminated','traitors_majority','final_fire','host_ended')),
    final_round         SMALLINT NOT NULL,
    full_reveal_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    summary             JSONB NOT NULL DEFAULT '{}'::jsonb
);
```

## Built in preset seed data

Store the five system presets in `game_rule_presets.rules`. Example rule shape:

```json
{
  "traitorCount": {"6": 2, "10": 2, "12": 3},
  "night": {"directMurder": true, "doubleMurderAfterRound": null},
  "tieRule": "revote_then_none",
  "roleReveal": "public",
  "veiledEndgameAtAlivePlayers": 4,
  "hiddenLegacy": {"enabled": false, "beforeRound": 3, "minimumAlivePlayers": 6},
  "poisonedGift": {"enabled": false, "uses": 0}
}
```

Recommended differences are: Classic Conspiracy has no powers; Midnight Heist enables one Poisoned Gift or True Shield; Blood Moon sets `doubleMurderAfterRound` to `2`; The Last Alibi sets `roleReveal` to `alternating`; and Final Gambit includes a one-use Faithful accusation plus no opening-night murder.

## Privacy and access controls

The schema is not by itself enough to protect secret roles. The application must enforce these query rules:

1. A Faithful player can read only their own `session_roles` row before full reveal.
2. A Traitor can read their own row and the identities of active fellow Traitors, but not unrevealed votes or private item payloads.
3. Public clients read only `game_events` with `audience = 'public'` plus safe player state fields.
4. Host-only views may read full state but must not be sent through a broadcast WebSocket channel.
5. Unrevealed votes and secret action targets are returned only to the trusted game reducer; final results may reveal them after `game_results.full_reveal_at`.

## Query patterns to index later if needed

- Current room game: `game_sessions(room_id, created_at DESC)`.
- Alive participants: `session_players(game_session_id, state)`.
- Event replay: `game_events(game_session_id, seq)`.
- Vote tally: `votes(game_round_id, target_session_player_id)`.
- Active traitor count: `session_roles(game_session_id, current_role)` joined to alive `session_players`.
