-- Career and daily personal bests reuse the existing Slay profile and coin ledger.
CREATE TABLE slay_solo_bests (
 user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 challenge_id TEXT NOT NULL, period TEXT NOT NULL,
 best_score DOUBLE PRECISION NOT NULL CHECK(best_score BETWEEN 0 AND 100),
 stars INTEGER NOT NULL CHECK(stars BETWEEN 1 AND 5),
 coins_awarded INTEGER NOT NULL DEFAULT 0 CHECK(coins_awarded>=0),
 xp_awarded INTEGER NOT NULL DEFAULT 0 CHECK(xp_awarded>=0),
 best_look UUID NOT NULL REFERENCES slay_looks(id),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,challenge_id,period)
);
CREATE INDEX slay_solo_ranking ON slay_solo_bests(period,challenge_id,best_score DESC);
-- The career keeps one character from start to finish (an avatar body plus a
-- character of that body); it is chosen once, before the first event.
ALTER TABLE slay_profiles
 ADD COLUMN career_body TEXT CHECK(career_body IN('female','male')),
 ADD COLUMN career_avatar TEXT,
 ADD CONSTRAINT slay_profiles_career_character CHECK((career_body IS NULL)=(career_avatar IS NULL));
