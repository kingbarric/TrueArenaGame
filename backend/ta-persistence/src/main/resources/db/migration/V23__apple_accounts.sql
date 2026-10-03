-- Apple's subject is stable even when the user hides or changes their email.
CREATE TABLE apple_accounts (
    subject TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX apple_accounts_user_id_uq ON apple_accounts(user_id);
