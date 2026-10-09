-- Games played and win rate only ever counted rated games (per-game record)
-- and the role-dealing game (lifetime stats), so Whot, casual Draughts,
-- Chess, Ludo… never showed up on anyone's profile. From now on every game
-- counts; this brings in the ones already in match history. Agents and
-- guests don't keep records.

-- Per game: unrated matches weren't counted (rated ones already were).
INSERT INTO player_game_stats (user_id, game_type, games_played, wins, losses, draws, last_played_at)
SELECT p.user_id, m.game_type,
       count(*),
       count(*) FILTER (WHERE p.outcome = 'won'),
       count(*) - count(*) FILTER (WHERE p.outcome = 'won') - count(*) FILTER (WHERE p.outcome = 'tied'),
       count(*) FILTER (WHERE p.outcome = 'tied'),
       max(m.completed_at)
FROM match_participants p
JOIN match_records m ON m.id = p.match_id
JOIN users u ON u.id = p.user_id
WHERE NOT m.ranked AND NOT u.is_bot AND NOT u.is_guest
GROUP BY p.user_id, m.game_type
ON CONFLICT (user_id, game_type) DO UPDATE SET
    games_played   = player_game_stats.games_played + EXCLUDED.games_played,
    wins           = player_game_stats.wins + EXCLUDED.wins,
    losses         = player_game_stats.losses + EXCLUDED.losses,
    draws          = player_game_stats.draws + EXCLUDED.draws,
    last_played_at = GREATEST(player_game_stats.last_played_at, EXCLUDED.last_played_at),
    updated_at     = now();

-- Lifetime: every recorded match, for anyone who has no lifetime row yet
-- (nobody outside the role-dealing game does).
INSERT INTO player_stats (group_id, user_id, games_played, wins)
SELECT NULL, p.user_id, count(*), count(*) FILTER (WHERE p.outcome = 'won')
FROM match_participants p
JOIN users u ON u.id = p.user_id
WHERE NOT u.is_bot AND NOT u.is_guest
  AND NOT EXISTS (SELECT 1 FROM player_stats s WHERE s.user_id = p.user_id AND s.group_id IS NULL)
GROUP BY p.user_id;
