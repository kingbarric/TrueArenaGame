-- Account deletion removes identifying records, while preserving other players'
-- aggregate results. This inert identity owns archived structural references only;
-- it cannot sign in, is excluded as a bot, and is never a system-pool agent.
INSERT INTO users(id, display_name, username, is_bot)
VALUES ('00000000-0000-4000-8000-000000000001', 'Deleted player', 'deleted_account_archive', true);

CREATE TABLE account_media_erasure (
    object_key TEXT PRIMARY KEY,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE users DROP CONSTRAINT users_owner_user_id_fkey,
 ADD CONSTRAINT users_owner_user_id_fkey FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE SET NULL;

-- These records belong to their user. Structural/shared ownership is handled
-- explicitly by erase_playhuud_account rather than cascading into other accounts.
ALTER TABLE messages DROP CONSTRAINT messages_sender_id_fkey,
 ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY(sender_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE roles DROP CONSTRAINT roles_user_id_fkey,
 ADD CONSTRAINT roles_user_id_fkey FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE votes DROP CONSTRAINT votes_voter_id_fkey, DROP CONSTRAINT votes_target_id_fkey,
 ADD CONSTRAINT votes_voter_id_fkey FOREIGN KEY(voter_id) REFERENCES users(id) ON DELETE CASCADE,
 ADD CONSTRAINT votes_target_id_fkey FOREIGN KEY(target_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE championship_participants DROP CONSTRAINT championship_participants_user_id_fkey,
 ADD CONSTRAINT championship_participants_user_id_fkey FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE championship_badges DROP CONSTRAINT championship_badges_user_id_fkey,
 ADD CONSTRAINT championship_badges_user_id_fkey FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE slay_looks DROP CONSTRAINT slay_looks_user_id_fkey,
 ADD CONSTRAINT slay_looks_user_id_fkey FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE slay_ballots DROP CONSTRAINT slay_ballots_voter_id_fkey,
 ADD CONSTRAINT slay_ballots_voter_id_fkey FOREIGN KEY(voter_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE slay_reward_claims DROP CONSTRAINT slay_reward_claims_user_id_fkey,
 ADD CONSTRAINT slay_reward_claims_user_id_fkey FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE content_reports DROP CONSTRAINT content_reports_reporter_id_fkey,
 ADD CONSTRAINT content_reports_reporter_id_fkey FOREIGN KEY(reporter_id) REFERENCES users(id) ON DELETE CASCADE;

CREATE FUNCTION erase_playhuud_account(target UUID) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE
    archive_id CONSTANT UUID := '00000000-0000-4000-8000-000000000001';
    identities UUID[];
    sessions UUID[];
    identity UUID;
BEGIN
    IF target = archive_id THEN RAISE EXCEPTION 'Cannot delete archive identity'; END IF;
    PERFORM id FROM users WHERE id=target AND NOT is_bot FOR UPDATE;
    IF NOT FOUND THEN RETURN false; END IF;
    WITH RECURSIVE owned(id) AS (
        SELECT target UNION SELECT u.id FROM users u JOIN owned o ON u.owner_user_id=o.id WHERE u.is_bot
    ) SELECT array_agg(id) INTO identities FROM owned;

    SELECT coalesce(array_agg(DISTINCT s.id), '{}'::UUID[]) INTO sessions
    FROM game_sessions s JOIN rooms r ON r.id=s.room_id
    WHERE r.host_id=ANY(identities) OR EXISTS (
        SELECT 1 FROM room_members m WHERE m.room_id=r.id AND m.user_id=ANY(identities)
    ) OR EXISTS (
        SELECT 1 FROM match_records mr JOIN match_participants mp ON mp.match_id=mr.id
        WHERE mr.game_session_id=s.id AND mp.user_id=ANY(identities)
    );
    INSERT INTO account_media_erasure(object_key)
        SELECT snapshot_key FROM slay_looks WHERE user_id=ANY(identities) AND snapshot_key IS NOT NULL
        ON CONFLICT DO NOTHING;

    -- Runtime/replay data contains identity-bearing player snapshots. End those
    -- games and remove their replay payloads; other players' rating records stay.
    UPDATE game_sessions SET ended_at=coalesce(ended_at,now()), runtime_state=NULL
        WHERE id=ANY(sessions);
    UPDATE rooms SET status='ended' WHERE id IN (SELECT room_id FROM game_sessions WHERE id=ANY(sessions));
    DELETE FROM game_events WHERE game_session_id=ANY(sessions);
    DELETE FROM championship_actions WHERE game_session_id=ANY(sessions) OR actor_id=ANY(identities);
    FOREACH identity IN ARRAY identities LOOP
        UPDATE game_results SET per_player_outcome=per_player_outcome-identity::TEXT
            WHERE game_session_id=ANY(sessions);
        -- Notification copies must not retain the deleted author's identity.
        DELETE FROM user_notifications WHERE data::TEXT LIKE '%'||identity::TEXT||'%';
        DELETE FROM issue_events WHERE user_id=identity OR detail LIKE '%'||identity::TEXT||'%';
    END LOOP;
    DELETE FROM issue_events WHERE EXISTS (
        SELECT 1 FROM users u WHERE u.id=ANY(identities) AND
        ((u.email IS NOT NULL AND position(u.email IN issue_events.detail)>0)
         OR (u.phone IS NOT NULL AND position(u.phone IN issue_events.detail)>0))
    );
    DELETE FROM player_reports WHERE reporter_id=ANY(identities) OR reported_id=ANY(identities)
        OR feed_post_id IN (SELECT id FROM feed_posts WHERE author_id=ANY(identities));
    DELETE FROM content_reports WHERE subject_id=ANY(identities)
        OR subject_id IN (SELECT id FROM slay_looks WHERE user_id=ANY(identities))
        OR subject_id IN (SELECT id FROM feed_posts WHERE author_id=ANY(identities));
    -- A competition's saved entries embed player IDs and outfit snapshots.
    DELETE FROM slay_competitions c WHERE c.host_id=ANY(identities) OR EXISTS (
        SELECT 1 FROM unnest(identities) i WHERE c.state::TEXT LIKE '%'||i::TEXT||'%'
    ) OR EXISTS (
        SELECT 1 FROM slay_looks l WHERE l.user_id=ANY(identities) AND c.state::TEXT LIKE '%'||l.id::TEXT||'%'
    );
    UPDATE game_sessions SET config_preset_id=NULL WHERE config_preset_id IN (
        SELECT p.id FROM game_config_preset p WHERE p.owner_user_id=ANY(identities)
        OR p.owner_group_id IN (SELECT id FROM groups WHERE created_by=ANY(identities))
    );
    DELETE FROM groups WHERE created_by=ANY(identities);
    DELETE FROM huud_spaces WHERE owner_id=ANY(identities) OR created_by=ANY(identities);
    UPDATE huud_spaces SET public_invite_room_id=NULL, public_invite_host_id=NULL,
        public_invite_seats=NULL, public_invite_at=NULL WHERE public_invite_host_id=ANY(identities);
    UPDATE rooms SET host_id=archive_id,status='ended' WHERE host_id=ANY(identities);
    UPDATE voice_sessions SET status='ended',ended_at=coalesce(ended_at,now()),
        owner_id=CASE WHEN owner_id=ANY(identities) THEN archive_id ELSE owner_id END,
        created_by=CASE WHEN created_by=ANY(identities) THEN archive_id ELSE created_by END
        WHERE owner_id=ANY(identities) OR created_by=ANY(identities);
    UPDATE voice_session_participants SET left_at=coalesce(left_at,now())
        WHERE voice_session_id IN (SELECT id FROM voice_sessions WHERE status='ended');
    UPDATE championships SET creator_id=archive_id,name='Archived tournament',
        status=CASE WHEN status='lobby' THEN 'cancelled' ELSE status END,
        completed_at=CASE WHEN status='lobby' THEN now() ELSE completed_at END
        WHERE creator_id=ANY(identities);
    UPDATE championships SET champion_id=NULL WHERE champion_id=ANY(identities);
    -- One UPDATE keeps the winner/player CHECK valid regardless of FK order.
    UPDATE championship_matches SET
        winner_id=CASE WHEN status IN ('active','pending') THEN
            CASE WHEN player_a=ANY(identities) AND NOT coalesce(player_b=ANY(identities),true) THEN player_b
                 WHEN player_b=ANY(identities) AND NOT coalesce(player_a=ANY(identities),true) THEN player_a
                 ELSE NULL END
            WHEN winner_id=ANY(identities) THEN NULL ELSE winner_id END,
        status=CASE WHEN status IN ('active','pending') THEN
            CASE WHEN (player_a=ANY(identities) AND NOT coalesce(player_b=ANY(identities),true))
                       OR (player_b=ANY(identities) AND NOT coalesce(player_a=ANY(identities),true))
                 THEN 'completed' ELSE 'no_winner' END ELSE status END,
        completed_at=CASE WHEN status IN ('active','pending') THEN now() ELSE completed_at END,
        a_absent_since=NULL,b_absent_since=NULL,clock_phase=NULL,clock_remaining_ms=NULL,
        player_a=CASE WHEN player_a=ANY(identities) THEN NULL ELSE player_a END,
        player_b=CASE WHEN player_b=ANY(identities) THEN NULL ELSE player_b END
        WHERE player_a=ANY(identities) OR player_b=ANY(identities) OR winner_id=ANY(identities);
    UPDATE championship_games SET winner_id=NULL WHERE winner_id=ANY(identities);
    DELETE FROM users WHERE id=ANY(identities);
    RETURN true;
END $$;
