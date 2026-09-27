-- AI agents ("bots") — a real player identity like a guest, but never signs
-- in and never needs a contact method. Canonical schema reference: docs/DATABASE.md.

ALTER TABLE users ADD COLUMN is_bot BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE users DROP CONSTRAINT users_phone_or_email_chk;
ALTER TABLE users ADD CONSTRAINT users_phone_or_email_chk
    CHECK (phone IS NOT NULL OR email IS NOT NULL OR is_guest OR is_bot);
