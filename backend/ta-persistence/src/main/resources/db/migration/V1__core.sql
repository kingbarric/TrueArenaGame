-- Phase 1 — durable core (accounts, friends, groups).
-- Canonical schema reference: docs/DATABASE.md.
--
-- Conventions used throughout every migration:
--   * surrogate UUID PK named `id`, defaulted with gen_random_uuid() (built in, PG 13+)
--   * natural keys are UNIQUE constraints, not the PK (Spring Data R2DBC has no
--     composite-key support)
--   * every enum-like TEXT column carries a CHECK for its domain
--   * timestamps are TIMESTAMPTZ, defaulted to now()

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
    role      TEXT        NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (group_id, user_id),
    CHECK (role IN ('owner', 'member'))
);

-- Friend pair stored with ordered ids so (a,b) and (b,a) can't both exist.
CREATE TABLE friends (
    id           UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    low_user_id  UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    high_user_id UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status       TEXT        NOT NULL,
    requested_by UUID        NOT NULL REFERENCES users (id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (low_user_id, high_user_id),
    CHECK (low_user_id < high_user_id),
    CHECK (status IN ('pending', 'accepted')),
    CHECK (requested_by IN (low_user_id, high_user_id))
);
