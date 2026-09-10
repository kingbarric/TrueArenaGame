-- Phase 9 — per-group player stats + a lifetime rollup.
-- Canonical schema reference: docs/DATABASE.md. Build Brief §6 / §11.
--
-- One row per (group_id, user_id); a NULL group_id row is that user's lifetime rollup
-- (ad-hoc / web-funnel games only touch the lifetime row). NULLS NOT DISTINCT (PG 15+)
-- makes the unique key treat the NULL group_id as a single slot per user.
--
-- Only counts are stored — rates like traitor win-rate are derived in queries.

CREATE TABLE player_stats (
    id                  UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    group_id            UUID        REFERENCES groups (id) ON DELETE CASCADE,   -- NULL = lifetime rollup
    user_id             UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    games_played        INT         NOT NULL DEFAULT 0,
    wins                INT         NOT NULL DEFAULT 0,
    traitor_games       INT         NOT NULL DEFAULT 0,
    traitor_wins        INT         NOT NULL DEFAULT 0,
    times_first_accused INT         NOT NULL DEFAULT 0,   -- first player voted for in a round
    current_win_streak  INT         NOT NULL DEFAULT 0,
    longest_win_streak  INT         NOT NULL DEFAULT 0,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE NULLS NOT DISTINCT (group_id, user_id),
    CHECK (wins <= games_played),
    CHECK (traitor_games <= games_played),
    CHECK (traitor_wins <= traitor_games),
    CHECK (current_win_streak <= longest_win_streak)
);
CREATE INDEX player_stats_user_id_idx ON player_stats (user_id);
