-- End-to-end encryption key material — an X25519 public key per user,
-- uploaded once per device on sign-in (see AppState._ensurePublicKey,
-- Flutter). The server only ever stores/relays public keys and ciphertext;
-- the private key never leaves the device, so this column is exactly as
-- sensitive as any other public identifier. Nullable: a user who hasn't
-- opened the app since this shipped (or is mid-upload) has no key yet, and
-- DM chat/calls fall back to unencrypted for that pair until both sides
-- have one — see ChatService/CallService.

ALTER TABLE users ADD COLUMN public_key TEXT;
