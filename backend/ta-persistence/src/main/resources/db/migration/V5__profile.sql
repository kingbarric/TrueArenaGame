-- Phase 10 — registration with phone or email, a unique editable username, and a
-- lifetime stats read path. Canonical schema reference: docs/DATABASE.md.
--
-- `phone` becomes optional (an account can register with email only), `email` is new
-- and optional the other way, and at least one of the two must be present. `username`
-- is a real handle now — unique, always set (auto-generated if the user didn't pick
-- one at signup), editable later via PATCH /me. `avatar_url` (already existed, unused
-- until now) doubles as the avatar slot: holds a bare emoji for a preset icon, or a
-- real URL once photo upload has somewhere to store files.

ALTER TABLE users
    ALTER COLUMN phone DROP NOT NULL,
    ADD COLUMN email TEXT,
    ADD COLUMN username TEXT;

-- Backfill existing rows (dev-seeded accounts) before the column is required.
UPDATE users SET username = 'player_' || substr(id::text, 1, 8) WHERE username IS NULL;

ALTER TABLE users
    ALTER COLUMN username SET NOT NULL,
    ADD CONSTRAINT users_username_key UNIQUE (username),
    ADD CONSTRAINT users_email_key UNIQUE (email),
    ADD CONSTRAINT users_phone_or_email_chk CHECK (phone IS NOT NULL OR email IS NOT NULL);
