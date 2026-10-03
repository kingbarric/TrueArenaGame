-- Whot and Goosi can identify a winner by player id or team name. The older
-- result constraint only allowed Traitors and team A/B labels.
ALTER TABLE game_results DROP CONSTRAINT game_results_winning_side_check;
ALTER TABLE game_results ADD CONSTRAINT game_results_winning_side_check
    CHECK (length(winning_side) > 0);

CREATE TABLE victory_statuses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    game_session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    game_type TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours'),
    UNIQUE (user_id, game_session_id)
);

CREATE INDEX victory_statuses_active_idx ON victory_statuses (expires_at, created_at DESC);
