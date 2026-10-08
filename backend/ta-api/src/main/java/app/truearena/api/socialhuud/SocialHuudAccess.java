package app.truearena.api.socialhuud;

import app.truearena.api.support.ApiExceptions;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import java.util.UUID;

/** Shared authorization, without depending on game or voice services. */
@Service
public class SocialHuudAccess {
    private final DatabaseClient db;
    public SocialHuudAccess(DatabaseClient db) { this.db=db; }
    public Mono<Boolean> mayView(UUID id, UUID user) {
        return db.sql("""
            SELECT EXISTS(SELECT 1 FROM huud_sessions h WHERE h.id=:id AND h.status='active'
              AND NOT EXISTS(SELECT 1 FROM huud_members m WHERE m.huud_id=h.id AND m.user_id=:user AND m.status='banned')
              AND NOT EXISTS(SELECT 1 FROM user_blocks b WHERE
                (b.blocker_id=h.owner_id AND b.blocked_id=:user) OR (b.blocker_id=:user AND b.blocked_id=h.owner_id))
              AND (h.owner_id=:user OR h.privacy='public'
                OR EXISTS(SELECT 1 FROM huud_members m WHERE m.huud_id=h.id AND m.user_id=:user AND m.status='participant')
                OR EXISTS(SELECT 1 FROM huud_admission a WHERE a.huud_id=h.id AND a.user_id=:user AND (a.can_view OR a.status IN ('invited','accepted')))
                OR (h.privacy='friends' AND EXISTS(SELECT 1 FROM friends f WHERE f.status='accepted'
                  AND f.low_user_id=LEAST(h.owner_id,:user) AND f.high_user_id=GREATEST(h.owner_id,:user))))) AS allowed
            """).bind("id",id).bind("user",user).map((r,m)->r.get("allowed",Boolean.class)).one();
    }
    public Mono<Void> requireView(UUID id, UUID user) {
        return mayView(id,user).filter(Boolean::booleanValue)
            .switchIfEmpty(Mono.error(ApiExceptions.forbidden("this Huud is private, ended, or unavailable to you"))).then();
    }
    public Mono<Void> requireParticipant(UUID id, UUID user) {
        return requireView(id,user).then(db.sql("SELECT 1 AS member FROM huud_members WHERE huud_id=:id AND user_id=:user AND status='participant'")
            .bind("id",id).bind("user",user).fetch().one())
            .switchIfEmpty(Mono.error(ApiExceptions.forbidden("request to join the Huud first"))).then();
    }
    public Mono<UUID> forGame(UUID room) {
        return db.sql("SELECT huud_session_id FROM rooms WHERE id=:room AND huud_session_id IS NOT NULL")
            .bind("room",room).map((r,m)->r.get("huud_session_id",UUID.class)).one();
    }
    public Mono<Void> requireGameView(UUID room, UUID user) {
        return forGame(room).flatMap(id->requireView(id,user));
    }
    public Mono<Void> requireGamePlayer(UUID room, UUID user) {
        return forGame(room).flatMap(id->requireParticipant(id,user).then(
            db.sql("SELECT EXISTS(SELECT 1 FROM huud_removed_game_players WHERE room_id=:room AND user_id=:user) AS removed")
                .bind("room",room).bind("user",user).map((r,m)->r.get("removed",Boolean.class)).one())
            .flatMap(removed->removed?Mono.error(ApiExceptions.forbidden("you are watching this match after leaving its roster")):Mono.empty()));
    }
    public Mono<Void> requireLegacyRoom(UUID room) {
        return forGame(room).flatMap(id->Mono.error(ApiExceptions.forbidden("manage this game's roster through the Huud admin")));
    }
}
