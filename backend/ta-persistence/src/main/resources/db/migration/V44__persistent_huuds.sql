-- A Huud is now a permanent room; going Live is a hangout inside it.
--
--   huud_spaces.status      'active' = the Huud exists; 'ended' = deleted.
--   huud_spaces.created_by  the owner, for good.
--   huud_spaces.owner_id    who's running it right now — the owner, or, while
--                           the owner is away during Live, whoever stepped in.
--   huud_spaces.live_since  set while Live; NULL = offline.
--   huud_space_members.left_at   only an explicit Leave (or being taken out)
--                                ends membership — being away never does.
--   huud_space_members.live_at   in the current Live hangout since; NULL = not in it.
--   huud_space_members.muted     no Live notifications from this Huud.

ALTER TABLE huud_spaces ADD COLUMN live_since TIMESTAMPTZ;
ALTER TABLE huud_space_members
    ADD COLUMN live_at TIMESTAMPTZ,
    ADD COLUMN muted   BOOLEAN NOT NULL DEFAULT false;

-- One Huud per owner (the creator), whoever happens to be hosting it.
DROP INDEX huud_spaces_one_owned;

-- Anyone who somehow has more than one Huud keeps the newest.
UPDATE huud_spaces s SET status = 'ended', ended_at = COALESCE(ended_at, now())
WHERE s.status = 'active' AND EXISTS (
    SELECT 1 FROM huud_spaces n
    WHERE n.created_by = s.created_by AND n.status = 'active' AND n.created_at > s.created_at);

CREATE UNIQUE INDEX huud_spaces_one_per_owner ON huud_spaces (created_by) WHERE status = 'active';

-- Huuds that are on right now are Live, with whoever is in them.
UPDATE huud_spaces SET live_since = created_at WHERE status = 'active';
UPDATE huud_space_members m SET live_at = m.joined_at
FROM huud_spaces s
WHERE s.id = m.huud_space_id AND s.status = 'active' AND m.left_at IS NULL AND NOT m.removed;

-- Everyone else's most recent Huud comes back as their permanent one —
-- offline, with its members, chat, code, privacy and background.
CREATE TEMP TABLE revived ON COMMIT DROP AS
SELECT DISTINCT ON (s.created_by) s.id
FROM huud_spaces s
WHERE s.status = 'ended'
  AND NOT EXISTS (SELECT 1 FROM huud_spaces a WHERE a.created_by = s.created_by AND a.status = 'active')
ORDER BY s.created_by, s.created_at DESC;

-- Its old code may since belong to a live Huud: those get a fresh one
-- (md5 hex mapped onto the code alphabet — no 0/O, 1/I/L).
UPDATE huud_spaces s
SET code = upper(substr(translate(md5(s.id::text || clock_timestamp()::text), '01', 'XY'), 1, 6))
WHERE s.id IN (SELECT id FROM revived)
  AND EXISTS (SELECT 1 FROM huud_spaces a WHERE a.status = 'active' AND a.code = s.code);

UPDATE huud_spaces s
SET status = 'active', ended_at = NULL, live_since = NULL, owner_id = s.created_by,
    current_room_id = NULL, shared_at = NULL
WHERE s.id IN (SELECT id FROM revived);

UPDATE huud_space_members m SET left_at = NULL, live_at = NULL, can_speak = false
WHERE m.huud_space_id IN (SELECT id FROM revived) AND NOT m.removed;

CREATE INDEX huud_space_members_live ON huud_space_members (huud_space_id) WHERE live_at IS NOT NULL;
