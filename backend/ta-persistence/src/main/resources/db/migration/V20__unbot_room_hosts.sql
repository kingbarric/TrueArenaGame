-- Rooms that ended up hosted by a Cyber Agent.
--
-- When a human host dropped out, the room was handed to the first player
-- still connected — and an agent connects over the socket like anyone else,
-- so a room left alone with a bot got a bot for a host. Such a room can't be
-- started, added to or ended by anybody, and rooms.host_id then pins the
-- bot's users row in place so the agent can never be deleted.
--
-- The cause is fixed in GameOrchestrator.migrateHost (people only). This
-- hands the existing rooms back: to the agent's owner where that's known,
-- otherwise to the first human who was in the room. Rooms whose only members
-- were ever bots keep their host — there's nobody to give them to, and
-- deleting such an agent reassigns the room at that point instead.

UPDATE rooms r
SET host_id = u.owner_user_id
FROM users u
WHERE u.id = r.host_id
  AND u.is_bot
  AND u.owner_user_id IS NOT NULL;

UPDATE rooms r
SET host_id = (
        SELECT m.user_id
        FROM room_members m
        JOIN users mu ON mu.id = m.user_id
        WHERE m.room_id = r.id
          AND NOT mu.is_bot
        ORDER BY m.joined_at
        LIMIT 1
    )
WHERE EXISTS (
        SELECT 1 FROM users u WHERE u.id = r.host_id AND u.is_bot
    )
  AND EXISTS (
        SELECT 1
        FROM room_members m
        JOIN users mu ON mu.id = m.user_id
        WHERE m.room_id = r.id AND NOT mu.is_bot
    );
