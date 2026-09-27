-- Coins — free/earned-only in-app currency (no real-money purchase, so no
-- payment integration and no gambling-law surface). A plain balance column
-- plus an append-only ledger, not just the balance alone: every change has
-- to be traceable, and a debit/credit pair (stakes, refunds) needs to be
-- auditable if something goes wrong. Canonical schema reference:
-- docs/DATABASE.md.

ALTER TABLE users ADD COLUMN coins BIGINT NOT NULL DEFAULT 0 CHECK (coins >= 0);

CREATE TABLE coin_transactions (
    id            UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    user_id       UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    delta         BIGINT      NOT NULL,
    balance_after BIGINT      NOT NULL,
    reason        TEXT        NOT NULL,
    ref_id        UUID,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (delta <> 0)
);

CREATE INDEX coin_transactions_user_idx ON coin_transactions (user_id, created_at DESC);
