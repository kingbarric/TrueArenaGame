-- Gives the bots that already existed before V17 an owner, so a player's
-- agents from before the change show up in their roster instead of being
-- invisible and unreachable.
--
-- Ownership is recovered from the rooms they were hired into: a bot only
-- ever joins a room because that room's host paid to add it, so the host of
-- the bot's earliest room is its creator, and that room's game is the game
-- it plays. Difficulty wasn't stored anywhere before V17, so these adopted
-- agents come back as medium — the default they were most likely created
-- with, and the player can always make a new one.
--
-- Bots that somehow belong to no room are left orphaned: there's nothing to
-- attribute them to, and they're already unreachable.

WITH first_room AS (
    SELECT DISTINCT ON (m.user_id)
           m.user_id AS bot_id,
           r.host_id,
           r.game_type
    FROM room_members m
    JOIN rooms r ON r.id = m.room_id
    JOIN users u ON u.id = m.user_id
    WHERE u.is_bot AND u.owner_user_id IS NULL
    ORDER BY m.user_id, m.joined_at
)
UPDATE users u
SET owner_user_id = f.host_id,
    bot_game_type = f.game_type,
    bot_difficulty = 'medium'
FROM first_room f
WHERE u.id = f.bot_id
  AND f.host_id <> u.id;
