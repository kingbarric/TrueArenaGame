-- The Huud feed (Your Huud / For you).
--
-- Only the things a player *says* live here: an open game request ("Ranked
-- Draughts, anyone?") and a direct challenge to one player. Everything else
-- the feed shows — wins, streaks, tournaments, champions — is read straight
-- from match_records / championships, so a feed card can never claim a win
-- the match history doesn't have.
--
-- A post always points at a real lobby room: posting creates the room, and
-- joining from the feed is the ordinary POST /rooms/join with its code. The
-- room going away (abandoned lobby) takes the post with it.

CREATE TABLE huud_posts (
    id             UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    author_id      UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind           TEXT        NOT NULL,
    room_id        UUID        NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    game_type      TEXT        NOT NULL,
    message        TEXT,
    ranked         BOOLEAN     NOT NULL DEFAULT false,
    -- How many players the author is gathering, author included. The room
    -- itself may hold more; the feed just stops advertising it once full.
    seats          INT         NOT NULL,
    -- Set for a challenge only: the one player it's addressed to.
    target_user_id UUID        REFERENCES users (id) ON DELETE CASCADE,
    status         TEXT        NOT NULL DEFAULT 'open',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at     TIMESTAMPTZ NOT NULL,
    answered_at    TIMESTAMPTZ,
    CHECK (kind IN ('game_request', 'challenge')),
    CHECK ((kind = 'challenge') = (target_user_id IS NOT NULL)),
    CHECK (target_user_id IS NULL OR target_user_id <> author_id),
    CHECK (status IN ('open', 'accepted', 'declined', 'closed')),
    CHECK (seats BETWEEN 2 AND 16),
    CHECK (message IS NULL OR length(message) <= 280),
    CHECK (expires_at > created_at)
);

-- The feed's read path: open, unexpired posts, newest first.
CREATE INDEX huud_posts_open_idx ON huud_posts (expires_at, created_at DESC) WHERE status = 'open';
-- "Challenges waiting for me".
CREATE INDEX huud_posts_target_idx ON huud_posts (target_user_id, status) WHERE kind = 'challenge';
CREATE INDEX huud_posts_author_idx ON huud_posts (author_id, status);
