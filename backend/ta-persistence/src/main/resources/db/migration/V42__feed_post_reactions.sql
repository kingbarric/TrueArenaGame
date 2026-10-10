-- One reaction per person per post, from a small kid-friendly set; tapping
-- the same one again takes it back.
CREATE TABLE feed_post_reactions (
    post_id    UUID        NOT NULL REFERENCES feed_posts (id) ON DELETE CASCADE,
    user_id    UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    emoji      TEXT        NOT NULL CHECK (emoji IN ('❤️', '👍', '😂', '😮', '🔥', '👏')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);
CREATE INDEX feed_post_reactions_post ON feed_post_reactions (post_id);
