-- Competitive identity, per-game skill ratings, and rankings.
-- Design record: docs/COMPETITIVE_IDENTITY.md · canonical schema: docs/DATABASE.md.
--
-- Game-agnostic throughout: `game_type` is a column, never a table name, so Chess
-- plugs in later without a second copy of any of this.

-- ---------------------------------------------------------------- PlayHuud number
--
-- Permanent, sequential, server-assigned, immutable, never recycled. A sequence
-- gives uniqueness and concurrency safety for free; the triggers below give
-- server-authority and immutability. Bots get NULL so Cyber Agents can never
-- consume a Founding 100 slot.

CREATE SEQUENCE playhuud_number_seq AS BIGINT START WITH 1;

ALTER TABLE users ADD COLUMN playhuud_number BIGINT;

-- Deterministic backfill of every existing human account: oldest account becomes
-- PlayHuud #000001. `id` breaks created_at ties so re-running this against a
-- restored snapshot produces identical numbers.
WITH ordered AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS n
    FROM users
    WHERE NOT is_bot
)
UPDATE users u SET playhuud_number = o.n FROM ordered o WHERE u.id = o.id;

SELECT setval('playhuud_number_seq', GREATEST(1, (SELECT coalesce(max(playhuud_number), 0) FROM users)));

ALTER TABLE users ADD CONSTRAINT users_playhuud_number_key UNIQUE (playhuud_number);

CREATE FUNCTION assign_playhuud_number() RETURNS TRIGGER AS $$
BEGIN
    -- Server-assigned, always: whatever the caller supplied is discarded.
    IF NEW.is_bot THEN
        NEW.playhuud_number := NULL;
    ELSE
        NEW.playhuud_number := nextval('playhuud_number_seq');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_assign_playhuud_number
    BEFORE INSERT ON users
    FOR EACH ROW EXECUTE FUNCTION assign_playhuud_number();

-- Immutable. A backstop rather than the mechanism (no service code writes it),
-- but a competitive identity nobody can renumber is worth enforcing in the one
-- place that cannot be bypassed.
CREATE FUNCTION freeze_playhuud_number() RETURNS TRIGGER AS $$
BEGIN
    NEW.playhuud_number := OLD.playhuud_number;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_freeze_playhuud_number
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION freeze_playhuud_number();

-- ---------------------------------------------------------------- competitive profile
--
-- Location decides leaderboard MEMBERSHIP only — there is exactly one skill
-- rating per game (player_game_ratings), and global/country/region rankings are
-- three views of that same number.

CREATE TABLE competitive_profiles (
    id                    UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    user_id               UUID        NOT NULL UNIQUE REFERENCES users (id) ON DELETE CASCADE,
    country_code          TEXT,                       -- ISO 3166-1 alpha-2, uppercase
    country_name          TEXT,
    region_code           TEXT,                       -- stable ISO 3166-2 style slug, e.g. NG-RI
    region_name           TEXT,
    city                  TEXT,
    -- City is optional and treated separately from the ranking location: it is
    -- never exposed on a public profile unless the player opts in.
    city_public           BOOLEAN     NOT NULL DEFAULT false,
    location_changes      INT         NOT NULL DEFAULT 0,
    location_updated_at   TIMESTAMPTZ,
    location_locked_until TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$'),
    CHECK (region_code IS NULL OR country_code IS NOT NULL),
    CHECK (location_changes >= 0)
);

-- ---------------------------------------------------------------- per-game skill rating
--
-- Glicko-2 state, one row per (user, game_type). There is deliberately no
-- universal cross-game rating: the unique key makes that a schema guarantee.
--
-- country_code/region_code are denormalised from competitive_profiles and kept
-- in sync by a trigger below. This is the one duplication in the design, and it
-- is what lets a country leaderboard be an index scan instead of a join + sort.

CREATE TABLE player_game_ratings (
    id                   UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    user_id              UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    game_type            TEXT        NOT NULL,
    rating               DOUBLE PRECISION NOT NULL DEFAULT 1500,
    rating_deviation     DOUBLE PRECISION NOT NULL DEFAULT 350,
    volatility           DOUBLE PRECISION NOT NULL DEFAULT 0.06,
    peak_rating          DOUBLE PRECISION NOT NULL DEFAULT 1500,
    rated_games_played   INT         NOT NULL DEFAULT 0,
    provisional          BOOLEAN     NOT NULL DEFAULT true,
    leaderboard_eligible BOOLEAN     NOT NULL DEFAULT false,
    country_code         TEXT,
    region_code          TEXT,
    last_rated_at        TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, game_type),
    CHECK (rated_games_played >= 0),
    CHECK (rating_deviation > 0),
    CHECK (volatility > 0)
);

-- Primary ordering is competitive rating, never game volume. Ties break on
-- rated_games_played then user_id so pagination is stable — without a
-- deterministic tiebreak two players on 1842 can swap between page requests and
-- one of them appears twice. The tiebreak lives on this row (not users) so a
-- "what's my rank" count stays an index-only scan.
CREATE INDEX player_game_ratings_global_idx
    ON player_game_ratings (game_type, rating DESC, rated_games_played DESC, user_id)
    WHERE leaderboard_eligible;
CREATE INDEX player_game_ratings_country_idx
    ON player_game_ratings (game_type, country_code, rating DESC, rated_games_played DESC, user_id)
    WHERE leaderboard_eligible;
CREATE INDEX player_game_ratings_region_idx
    ON player_game_ratings (game_type, country_code, region_code, rating DESC, rated_games_played DESC, user_id)
    WHERE leaderboard_eligible;
CREATE INDEX player_game_ratings_user_idx ON player_game_ratings (user_id);

-- A trigger, not service code, keeps the denormalised location in step: a new
-- write path cannot forget to call it.
CREATE FUNCTION sync_rating_location() RETURNS TRIGGER AS $$
BEGIN
    UPDATE player_game_ratings
       SET country_code = NEW.country_code, region_code = NEW.region_code
     WHERE user_id = NEW.user_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER competitive_profiles_sync_rating_location
    AFTER INSERT OR UPDATE OF country_code, region_code ON competitive_profiles
    FOR EACH ROW EXECUTE FUNCTION sync_rating_location();

-- ---------------------------------------------------------------- per-game statistics
--
-- The competitive stat line counts RANKED matches only — W/L/D, streaks and
-- top-100 wins are what a profile and a leaderboard row show, so they must not
-- be inflatable by beating a Cyber Agent or a casual alt. Casual human-vs-human
-- games are still counted, separately, in casual_games.
--
-- Counters only. Win rate is derived at read time, and tournament wins come
-- straight from championships.champion_id — a second counter for either would
-- just be another place to get them wrong. Everything here is reconstructable
-- from match_records + match_participants.

CREATE TABLE player_game_stats (
    id                 UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    user_id            UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    game_type          TEXT        NOT NULL,
    games_played       INT         NOT NULL DEFAULT 0,
    wins               INT         NOT NULL DEFAULT 0,
    losses             INT         NOT NULL DEFAULT 0,
    draws              INT         NOT NULL DEFAULT 0,
    current_win_streak INT         NOT NULL DEFAULT 0,
    best_win_streak    INT         NOT NULL DEFAULT 0,
    top100_wins        INT         NOT NULL DEFAULT 0,
    casual_games       INT         NOT NULL DEFAULT 0,
    last_played_at     TIMESTAMPTZ,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, game_type),
    CHECK (wins + losses + draws = games_played),
    CHECK (current_win_streak <= best_win_streak)
);
CREATE INDEX player_game_stats_user_idx ON player_game_stats (user_id);

-- ---------------------------------------------------------------- match history
--
-- Competitive history from day one, ranked AND casual. An unrated match is still
-- recorded with the reason it wasn't rated — that raw history is what later makes
-- rating farming, alt accounts and disconnect abuse investigable.

CREATE TABLE match_records (
    id               UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    -- The idempotency key. finishGame can legitimately run twice for a tournament
    -- room; an ON CONFLICT DO NOTHING insert reporting zero rows means "already
    -- rated", so a replay can never double-apply a rating change.
    game_session_id  UUID        UNIQUE REFERENCES game_sessions (id) ON DELETE SET NULL,
    room_id          UUID        REFERENCES rooms (id) ON DELETE SET NULL,
    championship_id  UUID        REFERENCES championships (id) ON DELETE SET NULL,
    game_type        TEXT        NOT NULL,
    ranked           BOOLEAN     NOT NULL,
    unranked_reason  TEXT,
    winning_side     TEXT,
    draw             BOOLEAN     NOT NULL DEFAULT false,
    player_count     INT         NOT NULL,
    started_at       TIMESTAMPTZ,
    completed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    duration_ms      BIGINT,
    rated_at         TIMESTAMPTZ,
    CHECK (ranked = (unranked_reason IS NULL)),
    CHECK (player_count >= 0)
);
CREATE INDEX match_records_game_type_idx ON match_records (game_type, completed_at DESC);
-- The repeat-opponent farming guard looks back over a pair's recent rated games.
CREATE INDEX match_records_ranked_recent_idx ON match_records (completed_at) WHERE ranked;
CREATE INDEX match_records_championship_idx ON match_records (championship_id) WHERE championship_id IS NOT NULL;

CREATE TABLE match_participants (
    id                      UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    match_id                UUID        NOT NULL REFERENCES match_records (id) ON DELETE CASCADE,
    user_id                 UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    outcome                 TEXT        NOT NULL,
    forfeited               BOOLEAN     NOT NULL DEFAULT false,
    disconnected            BOOLEAN     NOT NULL DEFAULT false,
    -- Null on an unrated match: nothing moved, and a 0.0 delta would read as
    -- "played a rated game and gained nothing".
    rating_before           DOUBLE PRECISION,
    rating_after            DOUBLE PRECISION,
    rating_delta            DOUBLE PRECISION,
    deviation_before        DOUBLE PRECISION,
    deviation_after         DOUBLE PRECISION,
    opponent_rating_before  DOUBLE PRECISION,   -- mean opponent rating, for multi-player games
    UNIQUE (match_id, user_id),
    CHECK (outcome IN ('won', 'lost', 'tied'))
);
-- The rating history read path: a player's matches newest first.
CREATE INDEX match_participants_user_idx ON match_participants (user_id, match_id);

-- ---------------------------------------------------------------- achievements
--
-- Generic model: the catalog (label, icon, priority, rarity) lives in code, so
-- adding a badge needs no migration and cannot drift from the logic that awards
-- it. Only the per-player fact lives here.
--
-- Founding badges are deliberately absent: they are a pure function of
-- playhuud_number, and materialising them would mean a row per account forever.

CREATE TABLE player_achievements (
    id               UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    user_id          UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    type             TEXT        NOT NULL,
    game_type        TEXT,                       -- null for cross-game achievements
    earned_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata         JSONB,
    display_priority INT         NOT NULL DEFAULT 0,
    rarity           TEXT        NOT NULL DEFAULT 'common',
    UNIQUE NULLS NOT DISTINCT (user_id, type, game_type),
    CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary'))
);
CREATE INDEX player_achievements_user_idx ON player_achievements (user_id, display_priority DESC);

-- ---------------------------------------------------------------- ranked vs casual
--
-- The host's REQUEST. The server decides a match's actual rated-ness at finish
-- time (RatedMatchPolicy) — a room flagged ranked that turns out to contain a
-- Cyber Agent is recorded unranked, with the reason.

ALTER TABLE rooms ADD COLUMN ranked BOOLEAN NOT NULL DEFAULT false;
