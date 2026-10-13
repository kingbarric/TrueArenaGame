-- The app's own "I'm open on PlayHuud" signal, kept apart from last_seen_at —
-- background voice, lingering sockets and game seats refresh that one too, so
-- it can't tell a Huud someone is actually using from one only a connection
-- left behind is holding. The Live list goes by this.
ALTER TABLE huud_space_members ADD COLUMN app_seen_at TIMESTAMPTZ;

UPDATE huud_space_members SET app_seen_at = last_seen_at WHERE live_at IS NOT NULL;
