-- Cyber Agents become persistent identities rather than throwaway rows.
--
-- Before this, every "add a Cyber Agent" minted a brand-new bot user that
-- was abandoned when the room ended, so a player re-entered its name and
-- difficulty for every single game. An agent is now owned by the player who
-- made it and can be re-hired into any later room of the same game — same
-- name, same difficulty, same identity.
--
-- The columns live on `users` (rather than a separate roster table) because
-- a bot already *is* a user row: it has an id, a display name, room
-- memberships and coin-free stats like any other player. A side table would
-- have duplicated that identity for no gain.

ALTER TABLE users ADD COLUMN owner_user_id UUID REFERENCES users (id) ON DELETE CASCADE;
ALTER TABLE users ADD COLUMN bot_game_type TEXT;
ALTER TABLE users ADD COLUMN bot_difficulty TEXT;

-- The one query this exists to serve: "my agents for this game".
CREATE INDEX users_bot_owner_idx ON users (owner_user_id, bot_game_type) WHERE is_bot;
