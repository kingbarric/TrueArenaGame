package app.truearena.api.calls;

import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.support.ApiExceptions;
import app.truearena.voice.LiveKitRoomAdmin;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Durable social membership, independent of websocket connections and game lifecycles. */
@Service
public class VoiceSessionService {
    public record Participant(UUID userId, String displayName, String avatarUrl, boolean muted, Instant joinedAt) {}
    public record VoiceSession(UUID voiceSessionId, String roomName, String type, UUID ownerId, UUID createdBy,
                               String privacy, String invitePermissions, UUID socialGroupId,
                               UUID activeGameSessionId, String status, Instant startedAt, Instant endedAt,
                               List<Participant> participants, List<Participant> joinRequests) {}
    private final DatabaseClient db;
    private final TransactionalOperator tx;
    private final InboxRegistry inbox;
    private final LiveKitRoomAdmin voice;
    public VoiceSessionService(DatabaseClient db, org.springframework.transaction.ReactiveTransactionManager manager, InboxRegistry inbox, LiveKitRoomAdmin voice) {
        this.db = db; this.tx = TransactionalOperator.create(manager); this.inbox = inbox; this.voice = voice;
    }

    /** Called only after the existing DM/group/game authorization checks. Rejoin preserves mute and joinedAt. */
    public Mono<VoiceSession> join(UUID user, String roomName) {
        if (roomName == null || roomName.length() > 100) return Mono.error(ApiExceptions.badRequest("invalid voice room"));
        return tx.transactional(lock("voice-user:" + user).then(lock("voice-room:" + roomName))
                .then(active(user)).flatMap(current -> current.roomName().equals(roomName)
                        ? heartbeat(user).thenReturn(current)
                        : Mono.error(ApiExceptions.conflict("you are currently in another voice session — leave it first")))
                .switchIfEmpty(Mono.defer(() -> ensure(roomName, user).flatMap(id ->
                        db.sql("INSERT INTO voice_session_participants(voice_session_id,user_id) VALUES(:id,:user) "
                                + "ON CONFLICT(voice_session_id,user_id) DO UPDATE SET left_at=NULL,last_seen_at=now(),joined_at=now()")
                                .bind("id", id).bind("user", user).fetch().rowsUpdated()
                                .then(Mono.defer(() -> {
                                    if (!roomName.startsWith("game-")) return Mono.empty();
                                    UUID game=UUID.fromString(roomName.substring(5));
                                    return db.sql("UPDATE rooms SET voice_session_id=:id WHERE id=:game AND NOT EXISTS(SELECT 1 FROM voice_sessions v WHERE v.id=rooms.voice_session_id AND v.status='active')")
                                            .bind("id",id).bind("game",game).fetch().rowsUpdated().then(gameStarted(game));
                                }))
                                .then(view(id)).doOnNext(session -> {
                                    inbox.joinCall(user, roomName);
                                    notifyMembers(session, "VOICE_USER_JOINED", user);
                                })))).doOnNext(s -> inbox.joinCall(user,roomName)));
    }

    private Mono<Void> lock(String key) {
        return db.sql("SELECT 1 AS locked FROM pg_advisory_xact_lock(hashtextextended(:key,0))").bind("key", key).fetch().all().then();
    }
    private Mono<UUID> ensure(String name, UUID user) {
        String type = name.startsWith("dm-") ? "direct" : "group";
        var sql = db.sql("INSERT INTO voice_sessions(room_name,type,owner_id,created_by,social_group_id) "
                + "VALUES(:name,:type,:user,:user,:group) ON CONFLICT(room_name) WHERE status='active' "
                + "DO UPDATE SET room_name=EXCLUDED.room_name RETURNING id")
                .bind("name",name).bind("type",type).bind("user",user);
        UUID group = null;
        if (name.startsWith("group-")) {
            try { group = UUID.fromString(name.substring(6)); } catch (IllegalArgumentException ignored) {}
        }
        sql = group == null ? sql.bindNull("group",UUID.class) : sql.bind("group",group);
        return sql.map((r,m) -> r.get("id",UUID.class)).one();
    }
    public Mono<VoiceSession> active(UUID user) {
        return db.sql("SELECT s.id FROM voice_sessions s JOIN voice_session_participants p ON p.voice_session_id=s.id "
                        + "WHERE p.user_id=:user AND p.left_at IS NULL AND s.status='active'")
                .bind("user",user).map((r,m) -> r.get("id",UUID.class)).one().flatMap(this::view);
    }
    public Mono<VoiceSession> view(UUID id) {
        return db.sql("SELECT * FROM voice_sessions WHERE id=:id").bind("id",id).fetch().one()
                .flatMap(row -> Mono.zip(
                    db.sql("SELECT p.*,u.display_name,u.avatar_url FROM voice_session_participants p JOIN users u ON u.id=p.user_id "
                            + "WHERE p.voice_session_id=:id AND p.left_at IS NULL ORDER BY p.joined_at")
                            .bind("id",id).map((r,m) -> new Participant(r.get("user_id",UUID.class),
                                    r.get("display_name",String.class),r.get("avatar_url",String.class),
                                    Boolean.TRUE.equals(r.get("muted",Boolean.class)),r.get("joined_at",Instant.class))).all().collectList(),
                    db.sql("SELECT i.user_id,i.created_at,u.display_name,u.avatar_url FROM voice_session_invites i JOIN users u ON u.id=i.user_id "
                            + "WHERE i.voice_session_id=:id AND i.status='requested'")
                            .bind("id",id).map((r,m) -> new Participant(r.get("user_id",UUID.class),r.get("display_name",String.class),
                                    r.get("avatar_url",String.class),false,r.get("created_at",Instant.class))).all().collectList())
                        .map(tuple -> new VoiceSession(id,(String)row.get("room_name"),(String)row.get("type"),
                                (UUID)row.get("owner_id"),(UUID)row.get("created_by"),(String)row.get("privacy"),
                                (String)row.get("invite_permissions"),(UUID)row.get("social_group_id"),
                                (UUID)row.get("active_game_session_id"),(String)row.get("status"),
                                instant(row.get("started_at")),instant(row.get("ended_at")),tuple.getT1(),tuple.getT2())));
    }
    private static Instant instant(Object value) {
        if (value == null) return null;
        if (value instanceof Instant instant) return instant;
        return ((java.time.OffsetDateTime)value).toInstant();
    }
    public Mono<Void> heartbeat(UUID user) {
        return db.sql("UPDATE voice_session_participants SET last_seen_at=now() WHERE user_id=:user AND left_at IS NULL")
                .bind("user",user).fetch().rowsUpdated().then();
    }
    public Mono<Void> mute(UUID user, boolean muted) {
        return db.sql("UPDATE voice_session_participants SET muted=:muted,last_seen_at=now() WHERE user_id=:user AND left_at IS NULL")
                .bind("user",user).bind("muted",muted).fetch().rowsUpdated().then();
    }
    public Mono<Void> leave(UUID user, String roomName) {
        return active(user).filter(s -> s.roomName().equals(roomName)).flatMap(s -> {
            if (s.ownerId().equals(user) && s.participants().size()>1) {
                return Mono.error(ApiExceptions.conflict("choose the next host before leaving"));
            }
            return voice.remove(roomName,user.toString()).onErrorResume(e -> Mono.empty())
                    .then(tx.transactional(lock("voice-room:"+roomName)
                            .then(db.sql("UPDATE voice_session_participants SET left_at=now() WHERE voice_session_id=:id AND user_id=:user")
                                    .bind("id",s.voiceSessionId()).bind("user",user).fetch().rowsUpdated())
                            .then(closeEmpty()).doOnSuccess(v -> {
                                inbox.leaveCall(user); notifyMembers(s,"VOICE_USER_LEFT",user);
                            })));
        });
    }
    private Mono<Void> closeEmpty() {
        return db.sql("UPDATE voice_sessions s SET status='ended',ended_at=now(),active_game_session_id=NULL "
                + "WHERE s.status='active' AND NOT EXISTS(SELECT 1 FROM voice_session_participants p WHERE p.voice_session_id=s.id AND p.left_at IS NULL)")
                .fetch().rowsUpdated().then();
    }
    public Mono<Void> requireOwner(UUID user, String roomName) {
        return active(user).filter(s -> s.roomName().equals(roomName) && s.ownerId().equals(user))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("only the host can do that"))).then();
    }
    public Mono<Void> requireInvitePermission(UUID user, String roomName) {
        return active(user).filter(s -> s.roomName().equals(roomName)
                        && (s.ownerId().equals(user) || "participants".equals(s.invitePermissions())))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("only the host can invite people"))).then();
    }
    public Mono<Void> delegate(UUID user, UUID next) {
        return active(user).switchIfEmpty(Mono.error(ApiExceptions.notFound("no active hangout"))).flatMap(s -> {
            if (!s.ownerId().equals(user) || s.participants().stream().noneMatch(p -> p.userId().equals(next))) {
                return Mono.error(ApiExceptions.forbidden("the host must choose a participant"));
            }
            return db.sql("UPDATE voice_sessions SET owner_id=:next WHERE id=:id AND owner_id=:user AND status='active'")
                    .bind("next",next).bind("id",s.voiceSessionId()).bind("user",user).fetch().rowsUpdated()
                    .doOnNext(n -> notifyMembers(s,"VOICE_HOST_CHANGED",next)).then();
        });
    }
    public Mono<Void> end(UUID user) {
        return active(user).flatMap(s -> requireOwner(user,s.roomName()).then(
                Flux.fromIterable(s.participants()).concatMap(p -> voice.remove(s.roomName(),p.userId().toString())
                        .onErrorResume(e -> Mono.empty())).then(tx.transactional(
                    db.sql("UPDATE voice_session_participants SET left_at=now() WHERE voice_session_id=:id AND left_at IS NULL")
                            .bind("id",s.voiceSessionId()).fetch().rowsUpdated().then(closeEmpty())))
                .doOnSuccess(v -> {
                    notifyMembers(s,"VOICE_ENDED",user);
                    s.participants().forEach(p -> inbox.leaveCall(p.userId()));
                })));
    }
    public Mono<Void> removeMembership(UUID user, String name) {
        return active(user).filter(s -> s.roomName().equals(name)).flatMap(s ->
                db.sql("UPDATE voice_session_participants SET left_at=now() WHERE voice_session_id=:id AND user_id=:user")
                        .bind("id",s.voiceSessionId()).bind("user",user).fetch().rowsUpdated()
                        .then(db.sql("INSERT INTO voice_session_invites(voice_session_id,user_id,status) VALUES(:id,:user,'rejected') "
                                + "ON CONFLICT(voice_session_id,user_id) DO UPDATE SET status='rejected',created_at=now()")
                                .bind("id",s.voiceSessionId()).bind("user",user).fetch().rowsUpdated())
                        .then(closeEmpty()).doOnSuccess(v -> { inbox.leaveCall(user); notifyMembers(s,"VOICE_USER_LEFT",user); }));
    }
    /** Link/unlink games without changing a single participant or voice status. */
    public Mono<Void> linkGame(UUID host, UUID game) {
        return active(host).flatMap(s -> tx.transactional(
            db.sql("UPDATE rooms SET voice_session_id=:id WHERE id=:game AND host_id=:host")
                    .bind("id",s.voiceSessionId()).bind("game",game).bind("host",host).fetch().rowsUpdated()
                    .flatMap(n -> n==0 ? Mono.empty() : gameStarted(game))));
    }
    public Mono<Void> gameStarted(UUID room) {
        return db.sql("UPDATE game_sessions g SET voice_session_id=r.voice_session_id FROM rooms r "
                        + "WHERE g.room_id=r.id AND r.id=:room AND g.ended_at IS NULL")
                .bind("room",room).fetch().rowsUpdated().then(
                    db.sql("UPDATE voice_sessions v SET active_game_session_id=(SELECT g.id FROM game_sessions g "
                            + "WHERE g.room_id=:room AND g.voice_session_id=v.id AND g.ended_at IS NULL ORDER BY g.started_at DESC LIMIT 1) "
                            + "WHERE v.status='active' AND EXISTS(SELECT 1 FROM rooms r WHERE r.id=:room AND r.voice_session_id=v.id)")
                            .bind("room",room).fetch().rowsUpdated().then());
    }
    public Mono<Void> gameEnded(UUID game) {
        return db.sql("UPDATE voice_sessions SET active_game_session_id=NULL WHERE active_game_session_id "
                        + "IN (SELECT id FROM game_sessions WHERE room_id=:game)")
                .bind("game",game).fetch().rowsUpdated().then();
    }
    public Mono<String> voiceRoomForGame(UUID game) {
        return db.sql("SELECT s.room_name FROM voice_sessions s JOIN rooms r ON r.voice_session_id=s.id WHERE r.id=:game AND s.status='active'")
                .bind("game",game).map((r,m) -> r.get("room_name",String.class)).one();
    }
    public Mono<Boolean> isMember(UUID user, String roomName) {
        return active(user).map(s -> s.roomName().equals(roomName)).defaultIfEmpty(false);
    }
    public Mono<Void> settings(UUID user, String privacy, String invites) {
        if (privacy == null || invites == null || !List.of("public","friends","invite_only","private").contains(privacy)
                || !List.of("host","participants").contains(invites)) return Mono.error(ApiExceptions.badRequest("invalid hangout settings"));
        return active(user).flatMap(s -> {
            if ("direct".equals(s.type()) && !List.of("invite_only","private").contains(privacy))
                return Mono.error(ApiExceptions.badRequest("encrypted direct calls require invitations"));
            return requireOwner(user,s.roomName()).then(
            db.sql("UPDATE voice_sessions SET privacy=:privacy,invite_permissions=:invites WHERE id=:id")
                    .bind("privacy",privacy).bind("invites",invites).bind("id",s.voiceSessionId()).fetch().rowsUpdated().then()); });
    }
    public Flux<VoiceSession> discover(UUID user) {
        return db.sql("SELECT s.id FROM voice_sessions s WHERE s.status='active' AND s.type='group' AND (s.privacy='public' OR "
                + "(s.privacy='friends' AND EXISTS(SELECT 1 FROM friends f WHERE f.status='accepted' "
                + "AND f.low_user_id=LEAST(s.owner_id,:user) AND f.high_user_id=GREATEST(s.owner_id,:user))) OR EXISTS(SELECT 1 FROM voice_session_invites i WHERE i.voice_session_id=s.id AND i.user_id=:user AND i.status='approved')) "
                + "ORDER BY s.started_at DESC LIMIT 50").bind("user",user).map((r,m) -> r.get("id",UUID.class)).all().concatMap(this::view);
    }
    public Mono<Void> requestJoin(UUID user, UUID id) {
        return view(id).filter(s -> "active".equals(s.status())).switchIfEmpty(Mono.error(ApiExceptions.notFound("hangout ended")))
                .flatMap(s -> discover(user).any(found -> found.voiceSessionId().equals(id)).filter(Boolean::booleanValue)
                        .switchIfEmpty(Mono.error(ApiExceptions.forbidden("this hangout does not allow join requests")))
                        .then(db.sql("INSERT INTO voice_session_invites(voice_session_id,user_id,status) VALUES(:id,:user,'requested') "
                                + "ON CONFLICT(voice_session_id,user_id) DO UPDATE SET status='requested',created_at=now()")
                                .bind("id",id).bind("user",user).fetch().rowsUpdated())
                        .doOnSuccess(v -> inbox.notify(s.ownerId(),Map.of("type","VOICE_JOIN_REQUEST","data",Map.of("userId",user,"voiceSessionId",id)))).then());
    }
    public Mono<Void> answerRequest(UUID host, UUID user, boolean approved) {
        return active(host).flatMap(s -> requireOwner(host,s.roomName()).then(
                db.sql("UPDATE voice_session_invites SET status=:status WHERE voice_session_id=:id AND user_id=:user AND status='requested'")
                        .bind("status",approved?"approved":"rejected").bind("id",s.voiceSessionId()).bind("user",user).fetch().rowsUpdated())
                .doOnNext(n -> { if(n>0) inbox.notify(user,Map.of("type","VOICE_JOIN_ANSWERED","data",
                        Map.of("approved",approved,"roomName",s.roomName()))); }).then());
    }
    public Mono<Void> recordInvite(String name, UUID user) {
        return db.sql("INSERT INTO voice_session_invites(voice_session_id,user_id,status) "
                + "SELECT id,:user,'invited' FROM voice_sessions WHERE room_name=:name AND status='active' "
                + "ON CONFLICT(voice_session_id,user_id) DO UPDATE SET status='invited',created_at=now()")
                .bind("name",name).bind("user",user).fetch().rowsUpdated().then();
    }
    public Mono<Boolean> removed(UUID user,String name) {
        return db.sql("SELECT EXISTS(SELECT 1 FROM voice_sessions s JOIN voice_session_invites i ON i.voice_session_id=s.id "
                + "WHERE s.room_name=:name AND s.status='active' AND i.user_id=:user AND i.status IN ('rejected','requested')) AS removed")
                .bind("name",name).bind("user",user).map((r,m) -> r.get("removed",Boolean.class)).one();
    }

    public Mono<Boolean> approved(UUID user, String name) {
        return db.sql("SELECT EXISTS(SELECT 1 FROM voice_sessions s JOIN voice_session_invites i ON i.voice_session_id=s.id "
                + "WHERE s.room_name=:name AND s.status='active' AND i.user_id=:user AND i.status IN ('approved','invited')) AS allowed")
                .bind("name",name).bind("user",user).map((r,m) -> r.get("allowed",Boolean.class)).one();
    }
    public Mono<Void> expireInactive() {
        return db.sql("UPDATE voice_session_participants SET left_at=now() WHERE left_at IS NULL AND last_seen_at<now()-INTERVAL '10 minutes' "
                + "RETURNING user_id,voice_session_id").fetch().all().concatMap(row -> view((UUID)row.get("voice_session_id"))
                        .flatMap(s -> voice.remove(s.roomName(),row.get("user_id").toString()).onErrorResume(e -> Mono.empty())
                                .doOnSuccess(v -> inbox.leaveCall((UUID)row.get("user_id")))))
                .then(db.sql("UPDATE voice_sessions s SET owner_id=(SELECT p.user_id FROM voice_session_participants p "
                        + "WHERE p.voice_session_id=s.id AND p.left_at IS NULL ORDER BY p.joined_at LIMIT 1) WHERE s.status='active' "
                        + "AND NOT EXISTS(SELECT 1 FROM voice_session_participants p WHERE p.voice_session_id=s.id AND p.user_id=s.owner_id AND p.left_at IS NULL) "
                        + "AND EXISTS(SELECT 1 FROM voice_session_participants p WHERE p.voice_session_id=s.id AND p.left_at IS NULL)").fetch().rowsUpdated())
                .then(closeEmpty());
    }
    private void notifyMembers(VoiceSession s, String type, UUID user) {
        for (Participant p:s.participants()) inbox.notify(p.userId(),Map.of("type",type,"data",
                Map.of("voiceSessionId",s.voiceSessionId(),"userId",user,"roomName",s.roomName())));
    }
}
