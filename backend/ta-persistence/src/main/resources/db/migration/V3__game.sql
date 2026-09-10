-- Phase 6/7 — the game: config presets, sessions, roles, event log, votes, results.
-- Canonical schema reference: docs/DATABASE.md · config model: docs/GAME_CONFIG.md §7.

CREATE TABLE game_config_preset (
    id              UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    scope           TEXT        NOT NULL,
    owner_group_id  UUID        REFERENCES groups (id) ON DELETE CASCADE,
    owner_user_id   UUID        REFERENCES users  (id) ON DELETE CASCADE,
    slug            TEXT,                                  -- set for builtins, null otherwise
    name            TEXT        NOT NULL,
    description     TEXT,
    tag             TEXT,
    config          JSONB       NOT NULL,
    catalog_version INT         NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (scope, slug),
    CHECK (scope IN ('builtin', 'group', 'user')),
    -- owner columns and slug must line up with the scope
    CHECK (
        (scope = 'builtin' AND slug IS NOT NULL AND owner_user_id IS NULL AND owner_group_id IS NULL)
     OR (scope = 'group'   AND slug IS NULL     AND owner_group_id IS NOT NULL AND owner_user_id IS NULL)
     OR (scope = 'user'    AND slug IS NULL     AND owner_user_id IS NOT NULL AND owner_group_id IS NULL)
    )
);
-- a group / a user can't have two saved presets with the same name
CREATE UNIQUE INDEX game_config_preset_user_name_uq  ON game_config_preset (owner_user_id, name)  WHERE scope = 'user';
CREATE UNIQUE INDEX game_config_preset_group_name_uq ON game_config_preset (owner_group_id, name) WHERE scope = 'group';

CREATE TABLE game_sessions (
    id               UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    room_id          UUID        NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    game_type        TEXT        NOT NULL DEFAULT 'truearena',
    config           JSONB       NOT NULL,
    config_preset_id UUID        REFERENCES game_config_preset (id),
    catalog_version  INT         NOT NULL,                 -- catalog the session runs under (from config)
    rng_seed         BIGINT      NOT NULL,
    phase            TEXT        NOT NULL DEFAULT 'Lobby',  -- engine-defined; not constrained here
    round            INT         NOT NULL DEFAULT 0,
    phase_ends_at    TIMESTAMPTZ,                          -- when the current timed phase elapses (null = untimed)
    started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at         TIMESTAMPTZ,
    CHECK (round >= 0)
);
CREATE INDEX game_sessions_room_id_idx ON game_sessions (room_id);

CREATE TABLE roles (
    id              UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    game_session_id UUID        NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    user_id         UUID        NOT NULL REFERENCES users (id),
    role_type       TEXT        NOT NULL,
    UNIQUE (game_session_id, user_id),
    CHECK (role_type IN ('traitor', 'faithful', 'recruited_traitor'))
);

CREATE TABLE game_events (
    id               UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    game_session_id  UUID        NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    seq              BIGINT      NOT NULL,
    type             TEXT        NOT NULL,
    payload          JSONB       NOT NULL,
    visibility_scope TEXT        NOT NULL,
    visibility_key   TEXT,                                 -- player id / role for scoped events; null for public
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (game_session_id, seq),
    CHECK (seq >= 1),
    CHECK (visibility_scope IN ('public', 'player', 'role')),
    CHECK ((visibility_scope = 'public') = (visibility_key IS NULL))
);

CREATE TABLE votes (
    id              UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    game_session_id UUID        NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    round           INT         NOT NULL,
    voter_id        UUID        NOT NULL REFERENCES users (id),
    target_id       UUID        NOT NULL REFERENCES users (id),
    UNIQUE (game_session_id, round, voter_id),
    CHECK (round >= 1),
    CHECK (voter_id <> target_id)
);

CREATE TABLE game_results (
    id                 UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    game_session_id    UUID        NOT NULL UNIQUE REFERENCES game_sessions (id) ON DELETE CASCADE,
    winning_side       TEXT        NOT NULL,
    per_player_outcome JSONB       NOT NULL,               -- { userId: "won" | "lost" }
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (winning_side IN ('faithful', 'traitors'))
);
