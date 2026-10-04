-- Cyber Agents are reusable system identities. Their player-facing name and
-- difficulty belong to one room membership, so the same pool identity can
-- safely serve simultaneous Huuds without being "busy" in another session.

ALTER TABLE room_members ADD COLUMN bot_difficulty TEXT;
ALTER TABLE room_members ADD CONSTRAINT room_members_bot_difficulty_chk
    CHECK (bot_difficulty IS NULL OR bot_difficulty IN ('easy', 'medium', 'hard'));

INSERT INTO users (display_name, username, is_bot, owner_user_id, bot_game_type, bot_difficulty)
SELECT 'Cyber Agent', 'system_agent_' || lpad(i::text, 2, '0'), true, NULL, 'system_pool', 'medium'
FROM generate_series(1, 32) AS pool(i)
ON CONFLICT (username) DO NOTHING;

CREATE INDEX users_system_agent_pool_idx ON users (username)
    WHERE is_bot AND owner_user_id IS NULL AND bot_game_type = 'system_pool';
