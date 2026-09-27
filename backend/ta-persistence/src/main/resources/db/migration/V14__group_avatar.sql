-- A group avatar — one of the same emoji presets a user's own profile icon
-- picks from (see docs/DEV_REFERENCE.md's avatar presets), so a group gets
-- the same "recognizable at a glance in a list" treatment as a person does.
-- No photo upload for groups yet, same as everywhere else emoji-only avatars
-- are the v1 scope — a plain nullable column, no new table needed.

ALTER TABLE groups ADD COLUMN avatar_emoji TEXT;
