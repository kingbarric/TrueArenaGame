-- Competitive profile visibility (docs/COMPETITIVE_IDENTITY.md §8.1).
--
-- Public by default — the point is a reputation people can see — but a player
-- can turn it off, leaving only name, avatar and PlayHuud number visible to
-- others. Leaderboards are unaffected: a rank is the board's fact, not the
-- profile's.
--
-- Its own migration rather than an edit to V32: V32 was already applied in
-- production before this column existed, and an applied migration is never
-- changed.

ALTER TABLE competitive_profiles
    ADD COLUMN profile_public BOOLEAN NOT NULL DEFAULT true;
