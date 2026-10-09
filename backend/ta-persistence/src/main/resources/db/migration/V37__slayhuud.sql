-- SlayHuud reuses users, rooms, sessions, coin ledger and competitive history.
CREATE TABLE slay_wardrobe (
 user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 item_id TEXT NOT NULL, source TEXT NOT NULL, acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,item_id)
);
CREATE TABLE slay_profiles (
 user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
 avatar JSONB, xp INTEGER NOT NULL DEFAULT 0 CHECK(xp>=0), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE slay_looks (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID NOT NULL REFERENCES users(id),
 look JSONB NOT NULL, catalog_version INTEGER NOT NULL, snapshot BYTEA,
 snapshot_verified BOOLEAN NOT NULL DEFAULT false,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), CHECK(snapshot IS NULL OR octet_length(snapshot)<=1048576)
);
CREATE INDEX slay_looks_user ON slay_looks(user_id,created_at DESC);
CREATE TABLE slay_competitions (
 id UUID PRIMARY KEY, room_id UUID UNIQUE REFERENCES rooms(id) ON DELETE CASCADE,
 host_id UUID REFERENCES users(id), mode TEXT NOT NULL CHECK(mode IN('battle','group','slay_or_pass','daily','weekly')),
 state JSONB NOT NULL, status TEXT NOT NULL, deadline TIMESTAMPTZ,
 settled BOOLEAN NOT NULL DEFAULT false, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX slay_due ON slay_competitions(deadline) WHERE deadline IS NOT NULL;
CREATE TABLE slay_ballots (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), competition_id UUID NOT NULL REFERENCES slay_competitions(id) ON DELETE CASCADE,
 voter_id UUID NOT NULL REFERENCES users(id), round INTEGER NOT NULL, entry_a TEXT NOT NULL, entry_b TEXT NOT NULL,
 chosen TEXT, served_at TIMESTAMPTZ NOT NULL DEFAULT now(), answered_at TIMESTAMPTZ,
 UNIQUE(competition_id,round,voter_id,entry_a,entry_b), CHECK(entry_a<entry_b),
 CHECK(chosen IS NULL OR chosen IN(entry_a,entry_b))
);
CREATE INDEX slay_ballot_voter ON slay_ballots(voter_id,served_at DESC);
CREATE TABLE slay_reward_claims (
 user_id UUID NOT NULL REFERENCES users(id), ref TEXT NOT NULL, claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,ref)
);
CREATE TABLE user_blocks (
 blocker_id UUID REFERENCES users(id) ON DELETE CASCADE, blocked_id UUID REFERENCES users(id) ON DELETE CASCADE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(blocker_id,blocked_id), CHECK(blocker_id<>blocked_id)
);
CREATE TABLE content_reports (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), reporter_id UUID NOT NULL REFERENCES users(id),
 subject_type TEXT NOT NULL, subject_id UUID NOT NULL, reason TEXT NOT NULL CHECK(length(reason) BETWEEN 1 AND 500),
 status TEXT NOT NULL DEFAULT 'open', created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE match_participants ADD COLUMN placement INTEGER CHECK(placement>=1);
-- 128-player cups reuse the same championship bracket; no second tournament system.
ALTER TABLE championships DROP CONSTRAINT IF EXISTS championships_size_check;
ALTER TABLE championships ADD CONSTRAINT championships_size_check CHECK(size IN (4,8,16,32,64,128));
ALTER TABLE rooms DROP CONSTRAINT rooms_game_type_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_game_type_check CHECK(game_type IN('truearena','wordbluff','draughts','goosi','whot','ludo','chess','slayhuud'));
