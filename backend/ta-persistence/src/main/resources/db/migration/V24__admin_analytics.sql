-- Admin analytics — login/session tracking and auth-failure signals, feeding
-- the /notvisible/analytics dashboard. Nothing here is read by the app itself.

CREATE TABLE login_events (
    id         UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    method     TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (method IN ('phone', 'email', 'google', 'apple', 'guest', 'refresh'))
);

CREATE INDEX login_events_user_idx ON login_events (user_id, created_at DESC);
CREATE INDEX login_events_created_idx ON login_events (created_at);

-- Best-effort operational signals (currently: failed OTP verification). Kept
-- deliberately small in scope — a general error-tracking pipeline is a much
-- bigger thing than this table claims to be.
CREATE TABLE issue_events (
    id         UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    user_id    UUID        REFERENCES users (id) ON DELETE SET NULL,
    type       TEXT        NOT NULL,
    detail     TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX issue_events_created_idx ON issue_events (created_at DESC);
CREATE INDEX issue_events_type_idx ON issue_events (type);
