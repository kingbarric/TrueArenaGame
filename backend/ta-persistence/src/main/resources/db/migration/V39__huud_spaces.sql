-- A Huud space is the persistent social place: people hang out, talk and play
-- one game after another in it. Games (rooms) come and go; the Huud stays
-- until its host ends it or everyone has gone.
CREATE TABLE huud_spaces (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code            TEXT        NOT NULL,
    name            TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
    privacy         TEXT        NOT NULL DEFAULT 'friends' CHECK (privacy IN ('friends', 'private', 'public')),
    owner_id        UUID        NOT NULL REFERENCES users (id),
    created_by      UUID        NOT NULL REFERENCES users (id),
    status          TEXT        NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'ended')),
    current_room_id UUID        REFERENCES rooms (id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at        TIMESTAMPTZ
);
CREATE UNIQUE INDEX huud_spaces_active_code ON huud_spaces (code) WHERE status = 'active';
-- One live Huud per host; ending it frees the slot (and the code).
CREATE UNIQUE INDEX huud_spaces_one_owned ON huud_spaces (owner_id) WHERE status = 'active';
CREATE INDEX huud_spaces_live ON huud_spaces (privacy, created_at DESC) WHERE status = 'active';

-- Everyone who has been in a Huud. Rows outlive the Huud so it shows in
-- each person's history with the people they played with.
CREATE TABLE huud_space_members (
    huud_space_id UUID        NOT NULL REFERENCES huud_spaces (id) ON DELETE CASCADE,
    user_id       UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- Arrival order for handing the host role on; reset when someone who
    -- left comes back, so they rejoin the end of the line.
    joined_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at       TIMESTAMPTZ,
    removed       BOOLEAN     NOT NULL DEFAULT false,
    PRIMARY KEY (huud_space_id, user_id)
);
CREATE INDEX huud_space_members_history ON huud_space_members (user_id, joined_at DESC);

ALTER TABLE rooms ADD COLUMN huud_space_id UUID REFERENCES huud_spaces (id) ON DELETE SET NULL;
CREATE INDEX rooms_huud_space ON rooms (huud_space_id) WHERE huud_space_id IS NOT NULL;
