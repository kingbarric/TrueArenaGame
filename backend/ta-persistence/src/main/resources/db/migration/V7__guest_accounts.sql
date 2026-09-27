-- Real guest identity: a device can create/join rooms without signing up first,
-- then "upgrade" in place (same user id, same room membership) by verifying a
-- phone or email later. Canonical schema reference: docs/DATABASE.md.

ALTER TABLE users
    ADD COLUMN is_guest BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN device_id TEXT;

-- A guest has neither phone nor email yet — widen the existing "at least one
-- contact method" rule to also allow that while is_guest is still true.
ALTER TABLE users DROP CONSTRAINT users_phone_or_email_chk;
ALTER TABLE users ADD CONSTRAINT users_phone_or_email_chk
    CHECK (phone IS NOT NULL OR email IS NOT NULL OR is_guest);

-- One guest row per device, so relaunching the app reuses the same identity
-- (and room membership) instead of minting a new guest every time.
CREATE UNIQUE INDEX users_device_id_uq ON users (device_id) WHERE device_id IS NOT NULL;
