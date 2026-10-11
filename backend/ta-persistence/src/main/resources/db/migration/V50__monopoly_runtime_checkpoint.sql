-- Private server checkpoint: dice/decks, deeds, trade offers, action dedupe and timer.
-- No public endpoint returns this column. Existing session DTOs remain unchanged.
ALTER TABLE game_sessions ADD COLUMN runtime_state JSONB;
