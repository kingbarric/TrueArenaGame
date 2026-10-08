package app.truearena.api.socialhuud;

import app.truearena.api.room.RoomService;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.ws.GameOrchestrator;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.room.RoomRuntimeRegistry;
import app.truearena.voice.LiveKitRoomAdmin;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Component;
import reactor.core.publisher.*;
import java.util.*;

/** Narrow adapter to existing game engines and LiveKit. No SlayHuud dependency. */
@Component
public class HuudGameBridge {
    private final DatabaseClient db;
    private final GameOrchestrator games;
    private final RoomService rooms;
    private final ObjectMapper mapper;
    private final LiveKitRoomAdmin voice;
    private final InboxRegistry inbox;
    private final RoomRuntimeRegistry runtimes;
    private final SocialHuudAccess access;
    public HuudGameBridge(DatabaseClient db,GameOrchestrator games,RoomService rooms,ObjectMapper mapper,
        LiveKitRoomAdmin voice,InboxRegistry inbox,RoomRuntimeRegistry runtimes,SocialHuudAccess access) {
        this.db=db;this.games=games;this.rooms=rooms;this.mapper=mapper;this.voice=voice;this.inbox=inbox;this.runtimes=runtimes;this.access=access;
    }
    public Mono<UUID> allocate(UUID huud,UUID host,String type,Map<String,Object> config,List<UUID> roster) {
        return Mono.fromCallable(()->mapper.writeValueAsString(config)).flatMap(json->
            db.sql("INSERT INTO rooms(code,host_id,game_type,game_config,huud_session_id,voice_session_id) VALUES(:code,:host,:type,:config,:huud,(SELECT id FROM voice_sessions WHERE room_name=:voice AND status='active')) RETURNING id")
                .bind("code",UUID.randomUUID().toString()).bind("host",host).bind("type",type).bind("config",json)
                .bind("huud",huud).bind("voice","huud-"+huud).map((r,m)->r.get("id",UUID.class)).one())
            .flatMap(room->Flux.fromIterable(roster).concatMap(user->
                db.sql("INSERT INTO room_members(room_id,user_id,nickname) SELECT :room,:user,username FROM users WHERE id=:user")
                    .bind("room",room).bind("user",user).fetch().rowsUpdated()).then(Mono.just(room)));
    }
    public Mono<Void> start(UUID room,UUID host) { return games.startHuudMatch(room,host); }
    public Mono<RoomView> view(UUID room,UUID user) { return rooms.get(room,user); }
    public Mono<Void> cancel(UUID room) { return games.cancelHuudMatch(room); }
    public Mono<Void> removePlayer(UUID room,UUID user) {
        return db.sql("SELECT 1 AS player FROM room_members WHERE room_id=:room AND user_id=:user")
            .bind("room",room).bind("user",user).fetch().one().flatMap(row->
                db.sql("INSERT INTO huud_removed_game_players(room_id,user_id) VALUES(:room,:user) ON CONFLICT DO NOTHING")
                    .bind("room",room).bind("user",user).fetch().rowsUpdated()
                    .then(Mono.fromRunnable(()->runtimes.find(room).ifPresent(rt->rt.revoke(user.toString()))))
                    .then(games.forfeitHuudPlayer(room,user)))
            .then(Mono.fromRunnable(()->runtimes.find(room).ifPresent(rt->rt.revoke(user.toString()))));
    }
    /** Existing sockets lose access immediately when a privacy change or block removes visibility. */
    public Mono<Void> recheckAccess(UUID huud) {
        return db.sql("SELECT id FROM rooms WHERE huud_session_id=:huud").bind("huud",huud)
            .map((r,m)->r.get("id",UUID.class)).all().concatMap(room->runtimes.find(room).map(rt->{
                Set<String> connected=new HashSet<>(rt.connectedUserIds);
                connected.addAll(rt.spectatorUserIds);
                return Flux.fromIterable(connected).concatMap(user->access.mayView(huud,UUID.fromString(user))
                    .doOnNext(allowed->{ if(!allowed) rt.revoke(user); })).then();
            }).orElseGet(Mono::empty)).then();
    }
    public Mono<Void> removeVoice(UUID huud,UUID user) {
        String name="huud-"+huud;
        return db.sql("UPDATE voice_session_participants p SET left_at=now() FROM voice_sessions s WHERE s.id=p.voice_session_id AND s.room_name=:name AND p.user_id=:user AND p.left_at IS NULL")
            .bind("name",name).bind("user",user).fetch().rowsUpdated().doOnNext(n->{
                if(n>0) { inbox.leaveCall(user);inbox.notify(user,Map.of("type","VOICE_ENDED","data",Map.of("roomName",name))); }
            }).then(db.sql("INSERT INTO huud_voice_revocations(huud_id,user_id) VALUES(:huud,:user) ON CONFLICT DO NOTHING")
                .bind("huud",huud).bind("user",user).fetch().rowsUpdated())
            .then(revokeVoice(huud,user));
    }
    private Mono<Void> revokeVoice(UUID huud,UUID user) {
        return voice.remove("huud-"+huud,user.toString()).then(
            db.sql("DELETE FROM huud_voice_revocations WHERE huud_id=:huud AND user_id=:user")
                .bind("huud",huud).bind("user",user).fetch().rowsUpdated()).then()
            .onErrorResume(e->{org.slf4j.LoggerFactory.getLogger(getClass()).warn("Huud voice removal queued for retry: {}",huud);return Mono.empty();});
    }
    public Mono<Void> retryVoiceRevocations() {
        return db.sql("SELECT huud_id,user_id FROM huud_voice_revocations").fetch().all()
            .concatMap(row->revokeVoice((UUID)row.get("huud_id"),(UUID)row.get("user_id"))).then();
    }
    public Mono<Void> muteVoice(UUID huud,UUID user) { return voice.muteAudio("huud-"+huud,user.toString()); }
    public Mono<Void> endVoice(UUID huud) {
        String name="huud-"+huud;
        return db.sql("SELECT p.user_id FROM voice_session_participants p JOIN voice_sessions s ON s.id=p.voice_session_id WHERE s.room_name=:name AND s.status='active' AND p.left_at IS NULL")
            .bind("name",name).map((r,m)->r.get("user_id",UUID.class)).all().concatMap(user->removeVoice(huud,user)).then(
            db.sql("UPDATE voice_sessions SET status='ended',ended_at=now(),active_game_session_id=NULL WHERE room_name=:name AND status='active'")
                .bind("name",name).fetch().rowsUpdated()).then();
    }
}
