-- Phase 6/7 — the game: config presets, sessions, roles, event log, votes, results.
-- docs/GAME_CONFIG.md §7 + Architecture §2.3.

CREATE TABLE game_config_preset (
    id              UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    scope           TEXT        NOT NULL,                 -- 'builtin' | 'group' | 'user'
    owner_group_id  UUID        REFERENCES groups (id) ON DELETE CASCADE,
    owner_user_id   UUID        REFERENCES users  (id) ON DELETE CASCADE,
    slug            TEXT,                                  -- 'blood_moon' … for builtins; null otherwise
    name            TEXT        NOT NULL,
    description     TEXT,
    tag             TEXT,
    config          JSONB       NOT NULL,
    catalog_version INT         NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (scope, slug)
);
CREATE INDEX game_config_preset_owner_user_idx  ON game_config_preset (owner_user_id);
CREATE INDEX game_config_preset_owner_group_idx ON game_config_preset (owner_group_id);

CREATE TABLE game_sessions (
    id               UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    room_id          UUID        NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    game_type        TEXT        NOT NULL DEFAULT 'truearena',
    config           JSONB       NOT NULL,
    config_preset_id UUID        REFERENCES game_config_preset (id),
    rng_seed         BIGINT      NOT NULL,
    phase            TEXT        NOT NULL DEFAULT 'Lobby',
    round            INT         NOT NULL DEFAULT 0,
    started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at         TIMESTAMPTZ
);
CREATE INDEX game_sessions_room_id_idx ON game_sessions (room_id);

CREATE TABLE roles (
    id              UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    game_session_id UUID        NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    user_id         UUID        NOT NULL REFERENCES users (id),
    role_type       TEXT        NOT NULL,                  -- traitor | faithful | recruited_traitor
    UNIQUE (game_session_id, user_id)
);

CREATE TABLE game_events (
    id               UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    game_session_id  UUID        NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    seq              BIGINT      NOT NULL,
    type             TEXT        NOT NULL,
    payload          JSONB       NOT NULL,
    visibility_scope TEXT        NOT NULL,                 -- public | player | role
    visibility_key   TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (game_session_id, seq)
);

CREATE TABLE votes (
    id              UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    game_session_id UUID        NOT NULL REFERENCES game_sessions (id) ON DELETE CASCADE,
    round           INT         NOT NULL,
    voter_id        UUID        NOT NULL REFERENCES users (id),
    target_id       UUID        NOT NULL REFERENCES users (id),
    UNIQUE (game_session_id, round, voter_id)
);

CREATE TABLE game_results (
    id                 UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    game_session_id    UUID        NOT NULL UNIQUE REFERENCES game_sessions (id) ON DELETE CASCADE,
    winning_side       TEXT        NOT NULL,
    per_player_outcome JSONB       NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
