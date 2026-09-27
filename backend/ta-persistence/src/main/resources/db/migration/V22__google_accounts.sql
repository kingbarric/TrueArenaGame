-- Google subject is stable across email changes. Keep it separate from the
-- contact email so returning users always reach the same TrueArena account.
CREATE TABLE google_accounts (
    subject TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX google_accounts_user_id_uq ON google_accounts(user_id);
