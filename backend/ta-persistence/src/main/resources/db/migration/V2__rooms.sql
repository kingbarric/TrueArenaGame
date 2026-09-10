-- Phase 3 — rooms. Canonical schema reference: docs/DATABASE.md.

CREATE TABLE rooms (
    id         UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    code       TEXT        NOT NULL UNIQUE,
    group_id   UUID        REFERENCES groups (id) ON DELETE SET NULL,  -- null = ad-hoc / web-funnel room
    host_id    UUID        NOT NULL REFERENCES users (id),
    status     TEXT        NOT NULL DEFAULT 'lobby',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (status IN ('lobby', 'in_game', 'ended'))
);
CREATE INDEX rooms_group_id_idx ON rooms (group_id);

CREATE TABLE room_members (
    id                UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    room_id           UUID        NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    user_id           UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    nickname          TEXT,
    connection_status TEXT        NOT NULL DEFAULT 'connected',
    ready_state       BOOLEAN     NOT NULL DEFAULT false,
    joined_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (room_id, user_id),
    CHECK (connection_status IN ('connected', 'disconnected'))
);
