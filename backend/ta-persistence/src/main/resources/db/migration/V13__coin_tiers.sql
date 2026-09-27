-- Coin tiers — status ladder over LIFETIME coins earned, not current balance,
-- so spending coins never demotes you (see docs/DATABASE.md). Tracked as its
-- own monotonic counter rather than derived from coin_transactions credits at
-- read time: cheap to read, and immune to any future transaction pruning.

ALTER TABLE users ADD COLUMN lifetime_coins BIGINT NOT NULL DEFAULT 0 CHECK (lifetime_coins >= 0);

-- Backfill from existing history so anyone who already earned coins keeps
-- credit for it instead of resetting to their current (possibly spent-down)
-- balance.
UPDATE users u
SET lifetime_coins = COALESCE((
    SELECT SUM(delta) FROM coin_transactions t WHERE t.user_id = u.id AND t.delta > 0
), 0);
