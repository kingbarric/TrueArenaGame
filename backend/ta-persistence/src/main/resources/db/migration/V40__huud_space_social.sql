-- Sharing a Huud to the feed: a short line ("Who wants to play Whot?") and
-- when it went up. Cleared when the host takes it down or the Huud ends.
ALTER TABLE huud_spaces
    ADD COLUMN feed_message TEXT CHECK (feed_message IS NULL OR char_length(feed_message) BETWEEN 1 AND 140),
    ADD COLUMN shared_at    TIMESTAMPTZ;
CREATE INDEX huud_spaces_shared ON huud_spaces (shared_at DESC) WHERE status = 'active' AND shared_at IS NOT NULL;

-- Being in a Huud means listening; talking is something the host hands out.
ALTER TABLE huud_space_members ADD COLUMN can_speak BOOLEAN NOT NULL DEFAULT false;

-- Asking the host: to come in (private Huuds, or a friends Huud you're not a
-- friend of), to play the game that's being set up, or for the mic. An
-- invitation from the host is a join row that starts out accepted.
CREATE TABLE huud_space_requests (
    huud_space_id UUID        NOT NULL REFERENCES huud_spaces (id) ON DELETE CASCADE,
    user_id       UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind          TEXT        NOT NULL CHECK (kind IN ('join', 'play', 'mic')),
    status        TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
    -- The game a play request is for; a new game starts a fresh queue.
    room_id       UUID        REFERENCES rooms (id) ON DELETE CASCADE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    answered_at   TIMESTAMPTZ,
    PRIMARY KEY (huud_space_id, user_id, kind)
);
CREATE INDEX huud_space_requests_pending ON huud_space_requests (huud_space_id, created_at) WHERE status = 'pending';

-- Huud chat: the conversation that carries on across games.
CREATE TABLE huud_space_messages (
    id            BIGSERIAL PRIMARY KEY,
    huud_space_id UUID        NOT NULL REFERENCES huud_spaces (id) ON DELETE CASCADE,
    user_id       UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    body          TEXT        NOT NULL CHECK (char_length(body) BETWEEN 1 AND 300),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX huud_space_messages_recent ON huud_space_messages (huud_space_id, id DESC);

-- Safety. Blocking someone keeps them out of your Huuds, hides their Huuds
-- and chat from you, and ends a friendship. (Named player_* because an
-- abandoned branch left an unused user_blocks table in production.)
CREATE TABLE player_blocks (
    blocker_id UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    blocked_id UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);
CREATE INDEX player_blocks_blocked ON player_blocks (blocked_id);

-- Reports go to the PlayHuud team; what was going on is kept with them.
CREATE TABLE player_reports (
    id            UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    reporter_id   UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    reported_id   UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    reason        TEXT        NOT NULL CHECK (reason IN ('mean', 'unsafe', 'spam', 'other')),
    details       TEXT        CHECK (details IS NULL OR char_length(details) <= 300),
    huud_space_id UUID        REFERENCES huud_spaces (id) ON DELETE SET NULL,
    message_id    BIGINT      REFERENCES huud_space_messages (id) ON DELETE SET NULL,
    message_body  TEXT,
    status        TEXT        NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewed')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (reporter_id <> reported_id)
);
CREATE INDEX player_reports_open ON player_reports (created_at) WHERE status = 'open';
