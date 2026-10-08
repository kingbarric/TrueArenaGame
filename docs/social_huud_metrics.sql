-- Run read-only against a migrated database. Add a created_at cohort filter as
-- needed. Exclude active Huuds for completed-duration reporting.

-- Multi-game Huud rate and average games per Huud (includes hangouts with zero games).
WITH started AS (
    SELECT huud_id, count(DISTINCT room_id) AS games
    FROM huud_events WHERE kind = 'GAME_STARTED' GROUP BY huud_id
)
SELECT avg((coalesce(s.games, 0) >= 2)::int)::numeric(8,4) AS multi_game_huud_rate,
       avg(coalesce(s.games, 0))::numeric(8,2) AS average_games_per_huud
FROM huud_sessions h LEFT JOIN started s ON s.huud_id = h.id;

-- Post-game retention: explicit 30-second-or-later presence sample, by population.
SELECT population, count(*) AS sampled_people,
       avg(retained::int)::numeric(8,4) AS post_game_retention
FROM huud_game_audience WHERE sampled_at IS NOT NULL GROUP BY population;

-- Viewer -> request -> started player conversion, per unique person/Huud.
WITH viewers AS (
    SELECT huud_id, actor_id AS user_id, min(created_at) AS first_view
    FROM huud_events WHERE kind = 'VIEW_STARTED' GROUP BY huud_id, actor_id
), converted AS (
    SELECT v.*, EXISTS (
        SELECT 1 FROM huud_events q
        JOIN huud_events start ON start.huud_id = q.huud_id
          AND start.activity_version = q.activity_version AND start.kind = 'GAME_STARTED'
        JOIN room_members m ON m.room_id = start.room_id AND m.user_id = q.actor_id
        WHERE q.kind = 'GAME_REQUESTED' AND q.huud_id = v.huud_id
          AND q.actor_id = v.user_id AND q.created_at >= v.first_view
    ) AS became_player FROM viewers v
)
SELECT count(*) AS viewer_huud_visits,
       avg(became_player::int)::numeric(8,4) AS viewer_to_player_conversion
FROM converted;

-- Request acceptance counts actual seats in a started game, not preliminary selections.
WITH requests AS (
    SELECT DISTINCT huud_id, activity_version, actor_id AS user_id
    FROM huud_events WHERE kind = 'GAME_REQUESTED'
)
SELECT count(*) AS play_requests,
       avg((EXISTS (
           SELECT 1 FROM huud_events e JOIN room_members m ON m.room_id = e.room_id
           WHERE e.kind = 'GAME_STARTED' AND e.huud_id = q.huud_id
             AND e.activity_version = q.activity_version AND m.user_id = q.user_id
       ))::int)::numeric(8,4) AS request_acceptance_rate
FROM requests q;

SELECT avg(extract(epoch FROM ended_at - created_at))::numeric(12,2)
       AS average_ended_huud_duration_seconds
FROM huud_sessions WHERE status = 'ended';

-- Return behavior: user created or was admitted into two different Huud sessions.
WITH visits AS (
    SELECT actor_id AS user_id, huud_id FROM huud_events WHERE kind = 'CREATED'
    UNION
    SELECT target_id AS user_id, huud_id FROM huud_events WHERE kind = 'JOIN_ACCEPTED'
), counts AS (
    SELECT user_id, count(*) AS sessions FROM visits GROUP BY user_id
)
SELECT count(*) AS participating_users,
       avg((sessions >= 2)::int)::numeric(8,4) AS huud_return_rate
FROM counts;
