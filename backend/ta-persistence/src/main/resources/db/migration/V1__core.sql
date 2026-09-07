-- Phase 1.1 — durable core (Architecture §2.3, Build Brief §6).
-- Surrogate UUID PKs everywhere (Spring Data R2DBC has no composite-key support);
-- natural keys kept as UNIQUE constraints. gen_random_uuid() is built in on PG 13+.

CREATE TABLE users (
    id           UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    display_name TEXT        NOT NULL,
    avatar_url   TEXT,
    phone        TEXT        NOT NULL UNIQUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE groups (
    id         UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    name       TEXT        NOT NULL,
    created_by UUID        NOT NULL REFERENCES users (id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE group_members (
    id        UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    group_id  UUID        NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
    user_id   UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role      TEXT        NOT NULL DEFAULT 'member', -- 'owner' | 'member'
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (group_id, user_id)
);

-- Friend pair stored with ordered ids so (a,b) and (b,a) can't both exist.
CREATE TABLE friends (
    id           UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    low_user_id  UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    high_user_id UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status       TEXT        NOT NULL, -- 'pending' | 'accepted'
    requested_by UUID        NOT NULL REFERENCES users (id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (low_user_id, high_user_id),
    CHECK (low_user_id < high_user_id)
);
