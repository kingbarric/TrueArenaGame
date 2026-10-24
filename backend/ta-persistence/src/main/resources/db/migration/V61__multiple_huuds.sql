-- Up to five Huuds each — one per circle: family, friends, everyone — with
-- one of them Live at a time, and each person in one Live hangout at a time.
-- The five is counted by the app server; the two "one at a time" rules are
-- kept here as well, so no race can break them.

DROP INDEX IF EXISTS huud_spaces_one_per_owner;
CREATE INDEX huud_spaces_owner ON huud_spaces (created_by) WHERE status = 'active';
CREATE UNIQUE INDEX huud_spaces_one_live_per_owner ON huud_spaces (created_by)
    WHERE status = 'active' AND live_since IS NOT NULL;

-- Anyone who is in more than one Live hangout stays in the one they walked
-- into last; the others just see them as away.
UPDATE huud_space_members m SET live_at = NULL, can_speak = false
WHERE m.live_at IS NOT NULL AND EXISTS (
    SELECT 1 FROM huud_space_members n
    WHERE n.user_id = m.user_id AND n.live_at IS NOT NULL
      AND (n.live_at > m.live_at OR (n.live_at = m.live_at AND n.huud_space_id > m.huud_space_id)));

CREATE UNIQUE INDEX huud_space_members_one_hangout ON huud_space_members (user_id) WHERE live_at IS NOT NULL;
