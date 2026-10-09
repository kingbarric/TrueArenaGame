-- Watching a Huud without joining it: who's looking in right now. The app
-- touches the row while the Huud is on screen; "watching" counts recent rows.
CREATE TABLE huud_space_viewers (
    huud_space_id UUID        NOT NULL REFERENCES huud_spaces (id) ON DELETE CASCADE,
    user_id       UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (huud_space_id, user_id)
);
CREATE INDEX huud_space_viewers_recent ON huud_space_viewers (huud_space_id, last_seen_at DESC);

-- Plain text posts on the feed ("Who's up for a game later?").
CREATE TABLE feed_posts (
    id         UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    author_id  UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    body       TEXT        NOT NULL CHECK (char_length(body) BETWEEN 1 AND 280),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);
CREATE INDEX feed_posts_recent ON feed_posts (created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX feed_posts_author ON feed_posts (author_id, created_at DESC);

-- Reports can be about a post, and the team marks them reviewed from the
-- web admin with a note.
ALTER TABLE player_reports
    ADD COLUMN feed_post_id UUID REFERENCES feed_posts (id) ON DELETE SET NULL,
    ADD COLUMN post_body    TEXT,
    ADD COLUMN reviewed_at  TIMESTAMPTZ,
    ADD COLUMN reviewed_by  TEXT,
    ADD COLUMN review_note  TEXT CHECK (review_note IS NULL OR char_length(review_note) <= 500);
