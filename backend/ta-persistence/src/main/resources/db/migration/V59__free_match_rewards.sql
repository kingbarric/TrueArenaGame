-- Retain all existing balances and ledger entries. Only remove entry-price metadata.
UPDATE rooms SET stake_coins=0 WHERE stake_coins<>0;
ALTER TABLE rooms ADD CONSTRAINT rooms_free_entry CHECK(stake_coins=0);
CREATE TABLE match_coin_rewards (
 game_session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
 user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 amount BIGINT NOT NULL CHECK(amount BETWEEN 0 AND 80),
 base_amount BIGINT NOT NULL, time_bonus BIGINT NOT NULL,
 elapsed_seconds BIGINT NOT NULL, vs_agent BOOLEAN NOT NULL,
 PRIMARY KEY(game_session_id,user_id)
);
-- Server-only settlement: the result and duration come from stored game records.
-- Lock before checking the receipt so concurrent retries cannot mint twice.
CREATE FUNCTION award_match_coins(session_id UUID, player_id UUID)
RETURNS SETOF match_coin_rewards LANGUAGE plpgsql AS $$
DECLARE outcome TEXT; duration BIGINT; benchmark BIGINT; base BIGINT;
 bonus BIGINT := 0; agent BOOLEAN; new_balance BIGINT; game TEXT; human_count BIGINT;
BEGIN
 PERFORM 1 FROM users WHERE id=player_id AND NOT is_bot FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 IF EXISTS(SELECT 1 FROM match_coin_rewards WHERE game_session_id=session_id AND user_id=player_id) THEN
   RETURN QUERY SELECT * FROM match_coin_rewards WHERE game_session_id=session_id AND user_id=player_id;
   RETURN;
 END IF;
 SELECT gr.per_player_outcome ->> player_id::TEXT,
        GREATEST(0,EXTRACT(EPOCH FROM(gs.ended_at-gs.started_at))::BIGINT),gs.game_type
 INTO outcome,duration,game FROM game_sessions gs JOIN game_results gr ON gr.game_session_id=gs.id
 WHERE gs.id=session_id AND gs.ended_at IS NOT NULL AND gs.started_at IS NOT NULL
 ORDER BY gr.created_at LIMIT 1;
 IF outcome IS NULL THEN RETURN; END IF;
 SELECT COALESCE(bool_or(u.is_bot),FALSE),COUNT(*) FILTER(WHERE NOT u.is_bot)
 INTO agent,human_count FROM game_results gr
 CROSS JOIN LATERAL jsonb_object_keys(gr.per_player_outcome::jsonb) AS p(player)
 JOIN users u ON u.id::TEXT=p.player WHERE gr.game_session_id=session_id;
 base := CASE outcome WHEN 'won' THEN 50 WHEN 'tied' THEN 15 WHEN 'lost' THEN 10 ELSE 0 END;
 IF agent OR human_count<2 THEN base:=0; END IF;
 benchmark := CASE game WHEN 'chess' THEN 300 WHEN 'draughts' THEN 300
   WHEN 'whot' THEN 120 WHEN 'ludo' THEN 180 WHEN 'goosi' THEN 180 ELSE 600 END;
 IF base=50 AND duration>=60 AND NOT EXISTS(SELECT 1 FROM game_events
   WHERE game_session_id=session_id AND type='GAME_OVER'
   AND COALESCE(payload->>'reason','') ~* 'resign|forfeit|timeout|abandon|disconnect') THEN
   bonus := 10*GREATEST(0,3-duration/benchmark);
 END IF;
 INSERT INTO match_coin_rewards VALUES(session_id,player_id,base+bonus,base,bonus,duration,agent);
 IF base+bonus>0 THEN
   UPDATE users SET coins=coins+base+bonus,lifetime_coins=lifetime_coins+base+bonus
     WHERE id=player_id RETURNING coins INTO new_balance;
   INSERT INTO coin_transactions(user_id,delta,balance_after,reason,ref_id)
     VALUES(player_id,base+bonus,new_balance,
       CASE outcome WHEN 'won' THEN 'match_win' WHEN 'tied' THEN 'match_tie' ELSE 'match_loss' END,session_id);
 END IF;
 RETURN QUERY SELECT * FROM match_coin_rewards WHERE game_session_id=session_id AND user_id=player_id;
END $$;
