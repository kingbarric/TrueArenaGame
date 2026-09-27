-- DM and group chat. Reuses `groups`/`group_members` (Phase 1) for group
-- membership; DM pairing follows the same ordered-pair convention as
-- `friends` (low_user_id < high_user_id by string/byte order — see
-- FriendRow.lowerOf's doc for why that's NOT UUID.compareTo).
-- Canonical schema reference: docs/DATABASE.md.

CREATE TABLE conversations (
    id              UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    type            TEXT        NOT NULL,
    dm_low_user_id  UUID REFERENCES users (id) ON DELETE CASCADE,
    dm_high_user_id UUID REFERENCES users (id) ON DELETE CASCADE,
    group_id        UUID REFERENCES groups (id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (type IN ('dm', 'group')),
    CHECK (
        (type = 'dm' AND dm_low_user_id IS NOT NULL AND dm_high_user_id IS NOT NULL
            AND dm_low_user_id < dm_high_user_id AND group_id IS NULL)
        OR
        (type = 'group' AND group_id IS NOT NULL AND dm_low_user_id IS NULL AND dm_high_user_id IS NULL)
    )
);

-- one conversation per DM pair / per group
CREATE UNIQUE INDEX conversations_dm_pair_idx ON conversations (dm_low_user_id, dm_high_user_id) WHERE type = 'dm';
CREATE UNIQUE INDEX conversations_group_idx ON conversations (group_id) WHERE type = 'group';

CREATE TABLE messages (
    id              UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    conversation_id UUID        NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    sender_id       UUID        NOT NULL REFERENCES users (id),
    kind            TEXT        NOT NULL,
    text            TEXT,
    room_id         UUID REFERENCES rooms (id) ON DELETE SET NULL,
    room_code       TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (kind IN ('text', 'game_invite')),
    CHECK (
        (kind = 'text' AND text IS NOT NULL)
        OR
        (kind = 'game_invite' AND room_id IS NOT NULL AND room_code IS NOT NULL)
    )
);

CREATE INDEX messages_conversation_idx ON messages (conversation_id, created_at);
