package app.truearena.api.socialhuud;

import app.truearena.api.socialhuud.SocialHuudDtos.*;
import app.truearena.api.support.ApiExceptions;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.persistence.UserRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.r2dbc.spi.Row;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.ReactiveTransactionManager;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.*;
import java.security.SecureRandom;
import java.time.*;
import java.util.*;
import java.util.function.Function;

/** Durable social session. Membership and game seats never share a table. */
@Service
public class SocialHuudService {
    record Session(UUID id,String code,UUID owner,String name,String description,String privacy,String status,
                   String activity,String gameType,Map<String,Object> config,int version,UUID room,Instant created) {}
    private final DatabaseClient db;
    private final TransactionalOperator tx;
    private final SocialHuudAccess access;
    private final HuudGameCatalog catalog;
    private final HuudGameBridge games;
    private final HuudTelemetry telemetry;
    private final UserRepository users;
    private final InboxRegistry inbox;
    private final ObjectMapper mapper;
    private final Duration grace;
    private final Duration idle;
    private static final SecureRandom RNG=new SecureRandom();
    public SocialHuudService(DatabaseClient db, ReactiveTransactionManager manager, SocialHuudAccess access,
        HuudGameCatalog catalog, HuudGameBridge games, HuudTelemetry telemetry, UserRepository users, InboxRegistry inbox, ObjectMapper mapper,
        @Value("${playhuud.huud.reconnect-grace:PT10M}") Duration grace,
        @Value("${playhuud.huud.inactivity-timeout:PT30M}") Duration idle) {
        this.db=db;this.tx=TransactionalOperator.create(manager);this.access=access;this.catalog=catalog;
        this.games=games;this.telemetry=telemetry;this.users=users;this.inbox=inbox;this.mapper=mapper;this.grace=grace;this.idle=idle;
    }
    private Mono<Void> lock(String key) {
        return db.sql("SELECT 1 AS locked FROM pg_advisory_xact_lock(hashtextextended(:key,0))")
            .bind("key",key).fetch().all().then();
    }
    private Session row(Row r) {
        Map<String,Object> config;
        try { config=mapper.readValue(r.get("game_config",io.r2dbc.postgresql.codec.Json.class).asString(),Map.class); }
        catch(Exception e) { throw new IllegalStateException("unreadable persisted Huud configuration",e); }
        return new Session(r.get("id",UUID.class),r.get("code",String.class),r.get("owner_id",UUID.class),
            r.get("name",String.class),r.get("description",String.class),r.get("privacy",String.class),
            r.get("status",String.class),r.get("activity",String.class),r.get("game_type",String.class),config,
            r.get("activity_version",Integer.class),r.get("current_room_id",UUID.class),r.get("created_at",Instant.class));
    }
    private Mono<Session> session(UUID id) {
        return db.sql("SELECT * FROM huud_sessions WHERE id=:id").bind("id",id).map((r,m)->row(r)).one()
            .switchIfEmpty(Mono.error(ApiExceptions.notFound("Huud not found")));
    }
    private Mono<Void> reconcile(UUID id) {
        return db.sql("""
            UPDATE huud_sessions h SET activity='results',last_activity_at=now()
            WHERE h.id=:id AND h.status='active' AND h.activity='playing'
              AND EXISTS(SELECT 1 FROM rooms r WHERE r.id=h.current_room_id AND r.status='ended')
            RETURNING owner_id,current_room_id,activity_version
            """).bind("id",id).fetch().one().flatMap(r->event(id,(UUID)r.get("owner_id"),null,
                (UUID)r.get("current_room_id"),(Integer)r.get("activity_version"),"GAME_COMPLETED")
                .then(telemetry.capture(id,(UUID)r.get("current_room_id"))));
    }
    private <T> Mono<T> change(UUID id,UUID user,boolean host,Function<Session,Mono<T>> action) {
        return tx.transactional(lock("huud:"+id).then(reconcile(id)).then(session(id)).flatMap(s->{
            if (!"active".equals(s.status())) return Mono.error(ApiExceptions.conflict("this Huud has ended"));
            if (host && !s.owner().equals(user)) return Mono.error(ApiExceptions.forbidden("only the Huud admin can do that"));
            return access.requireView(id,user).then(action.apply(s));
        }));
    }
    private static String name(String name,String fallback) {
        String result=name==null || name.isBlank()?fallback:name.strip();
        if(result.length()>80) throw ApiExceptions.badRequest("Huud name is too long");
        return result;
    }
    private static String privacy(String value) {
        String p=value==null?"public":value;
        if(!List.of("public","friends","private").contains(p)) throw ApiExceptions.badRequest("invalid Huud privacy");
        return p;
    }
    private String json(Object value) {
        try { return mapper.writeValueAsString(value); }
        catch(Exception e) { throw ApiExceptions.badRequest("invalid game settings"); }
    }
    public Mono<View> create(UUID owner,Create body) {
        return tx.transactional(lock("huud-owner:"+owner).then(ownedSession(owner))
            .flatMap(existing->lock("huud:"+existing.id()).then(reconcile(existing.id())).then(session(existing.id()))
                .flatMap(s->"idle".equals(s.activity()) && body.gameType()!=null
                    ? selectInside(s,body.gameType(),body.gameConfig()).thenReturn(s.id()) : Mono.just(s.id())))
            .switchIfEmpty(Mono.defer(()->users.findById(owner)
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("unknown user")))
                .flatMap(u->{
                    if(u.isGuest()) return Mono.error(ApiExceptions.forbidden("verify your account to create a Huud"));
                    String code=randomCode();
                    return db.sql("INSERT INTO huud_sessions(code,owner_id,name,description,privacy) VALUES(:code,:owner,:name,:description,:privacy) RETURNING id")
                        .bind("code",code).bind("owner",owner).bind("name",name(body.name(),u.username()+"'s Huud"))
                        .bind("description",body.description()==null?"":body.description()).bind("privacy",privacy(body.privacy()))
                        .map((r,m)->r.get("id",UUID.class)).one()
                        .flatMap(id->admit(id,owner).then(event(id,owner,null,null,0,"CREATED"))
                            .then(session(id)).flatMap(s->body.gameType()==null?Mono.just(id):
                                selectInside(s,body.gameType(),body.gameConfig()).thenReturn(id)));
                })))).flatMap(id->view(id,owner));
    }
    static String randomCode() {
        String alphabet="ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        StringBuilder code=new StringBuilder();
        for(int i=0;i<6;i++) code.append(alphabet.charAt(RNG.nextInt(alphabet.length())));
        return code.toString();
    }
    private Mono<Session> ownedSession(UUID owner) {
        return db.sql("SELECT * FROM huud_sessions WHERE owner_id=:owner AND status='active'")
            .bind("owner",owner).map((r,m)->row(r)).one();
    }
    public Mono<View> owned(UUID owner) { return ownedSession(owner).flatMap(s->view(s.id(),owner)); }
    public Flux<View> discover(UUID user) {
        return db.sql("SELECT id FROM huud_sessions WHERE status='active' AND privacy IN ('public','friends') ORDER BY created_at DESC LIMIT 100")
            .map((r,m)->r.get("id",UUID.class)).all().concatMap(id->access.mayView(id,user).flatMap(ok->ok?view(id,user):Mono.empty())).take(50);
    }
    public Mono<View> watchCode(UUID user,String code) {
        return db.sql("SELECT * FROM huud_sessions WHERE code=:code AND status='active'")
            .bind("code",code.toUpperCase(Locale.ROOT)).map((r,m)->row(r)).one()
            .switchIfEmpty(Mono.error(ApiExceptions.notFound("no active Huud with that code")))
            .flatMap(s->tx.transactional(lock("huud:"+s.id())
                .then("friends".equals(s.privacy())?access.requireView(s.id(),user):Mono.empty()).then(
                // A private code grants viewing access, not participant or mic permission.
                db.sql("INSERT INTO huud_admission(huud_id,user_id,status,can_view) VALUES(:id,:user,'invited',true) ON CONFLICT(huud_id,user_id) DO NOTHING")
                    .bind("id",s.id()).bind("user",user).fetch().rowsUpdated()).then(access.requireView(s.id(),user)))
                .then(heartbeat(s.id(),user)).then(view(s.id(),user)));
    }
    public Mono<View> view(UUID id,UUID user) {
        return access.requireView(id,user).then(reconcile(id)).then(session(id)).flatMap(s->
            Mono.zip(people(id,"participant"), admissions(id), requests(s), selected(s), viewerCount(id),
                ownStatus(id,user),requestStatus(s,user)).map(t->{
                    List<Person> members=t.getT1();
                    boolean participant=members.stream().anyMatch(p->p.userId().equals(user));
                    List<Person> joins=s.owner().equals(user)?t.getT2():List.of();
                    List<Person> reqs=s.owner().equals(user)?t.getT3():List.of();
                    return new View(id,s.code(),s.owner(),s.name(),s.description(),s.privacy(),s.status(),s.activity(),s.gameType(),
                        s.version(),s.room(),members.size(),t.getT5(),"playing".equals(s.activity())?t.getT4().size():0,participant,
                        t.getT6(),t.getT7(),s.gameType()==null?null:catalog.capacity(s.gameType(),s.config()),members,joins,reqs,t.getT4(),s.created());
                }));
    }
    private Mono<List<Person>> people(UUID id,String status) {
        return db.sql("SELECT m.user_id,u.username,u.display_name,u.avatar_url,m.status,m.joined_at FROM huud_members m JOIN users u ON u.id=m.user_id WHERE m.huud_id=:id AND m.status=:status ORDER BY m.joined_at")
            .bind("id",id).bind("status",status).map((r,m)->person(r)).all().collectList();
    }
    private static Person person(Row r) {
        return new Person(r.get("user_id",UUID.class),r.get("username",String.class),r.get("display_name",String.class),
            r.get("avatar_url",String.class),r.get("status",String.class),r.get("joined_at",Instant.class));
    }
    private Mono<List<Person>> admissions(UUID id) {
        return db.sql("SELECT a.user_id,u.username,u.display_name,u.avatar_url,a.status,a.updated_at AS joined_at FROM huud_admission a JOIN users u ON u.id=a.user_id WHERE a.huud_id=:id AND a.status='requested' ORDER BY a.updated_at")
            .bind("id",id).map((r,m)->person(r)).all().collectList();
    }
    private Mono<List<Person>> requests(Session s) {
        return db.sql("SELECT q.user_id,u.username,u.display_name,u.avatar_url,q.status,q.requested_at AS joined_at FROM huud_game_requests q JOIN users u ON u.id=q.user_id WHERE q.huud_id=:id AND q.activity_version=:version ORDER BY q.requested_at")
            .bind("id",s.id()).bind("version",s.version()).map((r,m)->person(r)).all().collectList();
    }
    private Mono<List<UUID>> selected(Session s) {
        return db.sql("SELECT q.user_id FROM huud_game_requests q WHERE q.huud_id=:id AND q.activity_version=:version AND q.status='selected' AND NOT EXISTS(SELECT 1 FROM huud_removed_game_players p WHERE p.room_id=:room AND p.user_id=q.user_id) ORDER BY q.requested_at")
            .bind("id",s.id()).bind("version",s.version()).bind("room",s.room()==null?new UUID(0,0):s.room())
            .map((r,m)->r.get("user_id",UUID.class)).all().collectList();
    }
    private Mono<Integer> viewerCount(UUID id) {
        return db.sql("SELECT count(*)::int AS n FROM huud_viewers v WHERE v.huud_id=:id AND v.last_seen_at>now()-interval '90 seconds' AND NOT EXISTS(SELECT 1 FROM huud_members m WHERE m.huud_id=v.huud_id AND m.user_id=v.user_id AND m.status='participant')")
            .bind("id",id).map((r,m)->r.get("n",Integer.class)).one();
    }
    private Mono<String> ownStatus(UUID id,UUID user) {
        return db.sql("SELECT status FROM huud_admission WHERE huud_id=:id AND user_id=:user").bind("id",id).bind("user",user)
            .map((r,m)->r.get("status",String.class)).one().defaultIfEmpty("none");
    }
    private Mono<String> requestStatus(Session s,UUID user) {
        return db.sql("SELECT status FROM huud_game_requests WHERE huud_id=:id AND activity_version=:version AND user_id=:user")
            .bind("id",s.id()).bind("version",s.version()).bind("user",user).map((r,m)->r.get("status",String.class)).one().defaultIfEmpty("none");
    }
    public Mono<Void> heartbeat(UUID id,UUID user) {
        return tx.transactional(lock("huud:"+id).then(access.requireView(id,user))
            .then(db.sql("INSERT INTO huud_viewers(huud_id,user_id) VALUES(:id,:user) ON CONFLICT(huud_id,user_id) DO UPDATE SET last_seen_at=now() RETURNING (xmax=0) AS entered")
            .bind("id",id).bind("user",user).map((r,m)->r.get("entered",Boolean.class)).one())
            .flatMap(entered->entered?access.requireParticipant(id,user).thenReturn(true)
                .onErrorResume(org.springframework.web.server.ResponseStatusException.class,e->Mono.just(false))
                .flatMap(member->member?Mono.empty():session(id).flatMap(s->event(s,user,null,"VIEW_STARTED"))):Mono.empty())
            .then(presenceInside(id,user)));
    }
    /** App-scoped heartbeat, never tied to which Huud screen is currently visible. */
    public Mono<Void> presence(UUID user) {
        return db.sql("SELECT id FROM huud_sessions WHERE status='active' AND (owner_id=:user OR EXISTS(SELECT 1 FROM huud_members m WHERE m.huud_id=huud_sessions.id AND m.user_id=:user AND m.status='participant')) ORDER BY id")
            .bind("user",user).map((r,m)->r.get("id",UUID.class)).all()
            .concatMap(id->tx.transactional(lock("huud:"+id).then(presenceInside(id,user)))).then();
    }
    private Mono<Void> presenceInside(UUID id,UUID user) {
        return db.sql("UPDATE huud_members SET last_seen_at=now() WHERE huud_id=:id AND user_id=:user AND status='participant'")
            .bind("id",id).bind("user",user).fetch().rowsUpdated().then(
            db.sql("UPDATE huud_sessions SET owner_seen_at=now() WHERE id=:id AND owner_id=:user AND status='active'")
                .bind("id",id).bind("user",user).fetch().rowsUpdated()).then();
    }
    public Mono<Void> stopViewing(UUID id,UUID user) {
        return db.sql("DELETE FROM huud_viewers WHERE huud_id=:id AND user_id=:user").bind("id",id).bind("user",user).fetch().rowsUpdated().then();
    }
    private Mono<Void> admit(UUID id,UUID user) {
        return db.sql("INSERT INTO huud_members(huud_id,user_id,status) VALUES(:id,:user,'participant') ON CONFLICT(huud_id,user_id) DO UPDATE SET status='participant',joined_at=now(),last_seen_at=now() WHERE huud_members.status<>'banned'")
            .bind("id",id).bind("user",user).fetch().rowsUpdated().flatMap(n->n>0?
                db.sql("DELETE FROM huud_voice_revocations WHERE huud_id=:id AND user_id=:user")
                    .bind("id",id).bind("user",user).fetch().rowsUpdated().then():Mono.empty());
    }
    public Mono<View> requestJoin(UUID id,UUID user) {
        return change(id,user,false,s->access.mayView(id,user).then(ownStatus(id,user)).flatMap(status->
            access.requireParticipant(id,user).thenReturn(true).onErrorResume(e->Mono.just(false)).flatMap(member->{
                if(member) return Mono.just(id);
                if("requested".equals(status)) return Mono.just(id);
                return rate(user,"JOIN_REQUESTED",5,60).then(db.sql("INSERT INTO huud_admission(huud_id,user_id,status) VALUES(:id,:user,'requested') ON CONFLICT(huud_id,user_id) DO UPDATE SET status='requested',updated_at=now()")
                    .bind("id",id).bind("user",user).fetch().rowsUpdated()).then(event(s,user,null,"JOIN_REQUESTED")).thenReturn(id);
            }))).flatMap(x->view(x,user));
    }
    public Mono<View> answerJoin(UUID id,UUID host,UUID target,boolean accepted) {
        return change(id,host,true,s->access.requireView(id,target).then(db.sql("UPDATE huud_admission SET status=:status,updated_at=now() WHERE huud_id=:id AND user_id=:user AND status='requested'")
            .bind("id",id).bind("user",target).bind("status",accepted?"accepted":"rejected").fetch().rowsUpdated())
            .flatMap(n->n==0?Mono.error(ApiExceptions.conflict("no pending Huud join request")):
                (accepted?admit(id,target):Mono.<Void>empty()).then(event(s,host,target,accepted?"JOIN_ACCEPTED":"JOIN_REJECTED"))).thenReturn(id))
            .flatMap(x->view(x,host));
    }
    public Mono<View> invite(UUID id,UUID host,UUID target) {
        return change(id,host,true,s->users.findById(target).switchIfEmpty(Mono.error(ApiExceptions.notFound("user not found")))
            .flatMap(u->db.sql("INSERT INTO huud_admission(huud_id,user_id,status,can_view) VALUES(:id,:user,'invited',true) ON CONFLICT(huud_id,user_id) DO UPDATE SET status='invited',can_view=true,updated_at=now() WHERE huud_admission.status<>'accepted'")
                .bind("id",id).bind("user",target).fetch().rowsUpdated()).then(event(s,host,target,"INVITED"))
            .doOnSuccess(v->inbox.notify(target,Map.of("type","HUUD_INVITE","data",Map.of("huudId",id,"name",s.name(),"code",s.code())))).thenReturn(id))
            .flatMap(x->view(x,host));
    }
    public Mono<View> settings(UUID id,UUID host,Settings body) {
        return change(id,host,true,s->db.sql("UPDATE huud_sessions SET name=:name,description=:description,privacy=:privacy WHERE id=:id")
            .bind("id",id).bind("name",name(body.name(),s.name())).bind("description",body.description()==null?"":body.description())
            .bind("privacy",privacy(body.privacy())).fetch().rowsUpdated().then(event(s,host,null,"SETTINGS_CHANGED")).then(games.recheckAccess(id)).thenReturn(id))
            .flatMap(x->view(x,host));
    }
    private static void expected(Session s,Integer version) {
        if(version!=null && s.version()!=version) throw ApiExceptions.conflict("the Huud game changed; refresh before trying again");
    }
    private static void waiting(Session s) {
        if(!"waiting".equals(s.activity())) throw ApiExceptions.conflict("game requests are not open");
    }
    private Mono<Void> selectInside(Session s,String type,Map<String,Object> config) {
        if("playing".equals(s.activity())) return Mono.error(ApiExceptions.conflict("finish the current match first"));
        Map<String,Object> normalized=catalog.config(type,config);
        return db.sql("UPDATE huud_sessions SET game_type=:type,game_config=CAST(:config AS jsonb),activity='waiting',activity_version=activity_version+1,current_room_id=NULL,last_activity_at=now() WHERE id=:id")
            .bind("id",s.id()).bind("type",type).bind("config",json(normalized)).fetch().rowsUpdated()
            .then(event(s.id(),s.owner(),null,null,s.version()+1,"GAME_SELECTED"));
    }
    public Mono<View> selectGame(UUID id,UUID host,Game game) {
        return change(id,host,true,s->{ expected(s,game.activityVersion()); return selectInside(s,game.gameType(),game.gameConfig()).thenReturn(id); }).flatMap(x->view(x,host));
    }
    public Mono<View> hangOut(UUID id,UUID host) {
        return change(id,host,true,s->{
            if("playing".equals(s.activity())) return Mono.error(ApiExceptions.conflict("finish the current match first"));
            return db.sql("UPDATE huud_sessions SET activity='idle',game_type=NULL,game_config='{}',current_room_id=NULL,activity_version=activity_version+1 WHERE id=:id")
                .bind("id",id).fetch().rowsUpdated().thenReturn(id);
        }).flatMap(x->view(x,host));
    }
    public Mono<View> requestGame(UUID id,UUID user) { return requestGame(id,user,null); }
    public Mono<View> requestGame(UUID id,UUID user,Integer version) {
        return change(id,user,false,s->{
            expected(s,version);
            waiting(s);
            return access.requireParticipant(id,user).then(requestStatus(s,user)).flatMap(status->{
                if(List.of("requested","selected").contains(status)) return Mono.just(id);
                return rate(user,"GAME_REQUESTED",10,60).then(db.sql("INSERT INTO huud_game_requests(huud_id,activity_version,user_id,status) VALUES(:id,:version,:user,'requested') ON CONFLICT(huud_id,activity_version,user_id) DO UPDATE SET status='requested',requested_at=now()")
                    .bind("id",id).bind("version",s.version()).bind("user",user).fetch().rowsUpdated()).then(event(s,user,null,"GAME_REQUESTED")).thenReturn(id);
            });
        }).flatMap(x->view(x,user));
    }
    public Mono<View> selectPlayer(UUID id,UUID host,UUID target,boolean chosen) { return selectPlayer(id,host,target,chosen,null); }
    public Mono<View> selectPlayer(UUID id,UUID host,UUID target,boolean chosen,Integer version) {
        return change(id,host,true,s->{
            expected(s,version);
            waiting(s);
            return access.requireParticipant(id,target).then(requestStatus(s,target)).flatMap(status->{
                if(chosen && !target.equals(host) && !List.of("requested","selected","not_selected").contains(status))
                    return Mono.error(ApiExceptions.conflict("this participant has not requested to play"));
                return selected(s).flatMap(roster->{
                    if(chosen && !roster.contains(target) && roster.size()>=catalog.entry(s.gameType(),s.config()).capacity().max())
                        return Mono.error(ApiExceptions.conflict("all game seats are selected"));
                    return db.sql("INSERT INTO huud_game_requests(huud_id,activity_version,user_id,status) VALUES(:id,:version,:user,:status) ON CONFLICT(huud_id,activity_version,user_id) DO UPDATE SET status=EXCLUDED.status")
                        .bind("id",id).bind("version",s.version()).bind("user",target).bind("status",chosen?"selected":"not_selected")
                        .fetch().rowsUpdated().then(event(s,host,target,chosen?"PLAYER_SELECTED":"PLAYER_NOT_SELECTED")).thenReturn(id);
                });
            });
        }).flatMap(x->view(x,host));
    }
    public Mono<Match> start(UUID id,UUID host) { return start(id,host,null); }
    public Mono<Match> start(UUID id,UUID host,Integer version) {
        return change(id,host,true,s->{
            expected(s,version);
            waiting(s);
            return selected(s).flatMap(roster->{
                catalog.entry(s.gameType(),s.config()).validate(roster);
                return Flux.fromIterable(roster).concatMap(u->access.requireParticipant(id,u)).then(
                    games.allocate(id,host,s.gameType(),s.config(),roster)).flatMap(room->
                    db.sql("UPDATE huud_sessions SET activity='playing',current_room_id=:room,last_activity_at=now() WHERE id=:id")
                        .bind("id",id).bind("room",room).fetch().rowsUpdated()
                        .then(db.sql("UPDATE huud_game_requests SET status='closed' WHERE huud_id=:id AND activity_version=:version AND status<>'selected'")
                            .bind("id",id).bind("version",s.version()).fetch().rowsUpdated()).then(Mono.just(room)));
            });
        }).flatMap(room->games.start(room,host)
            .then(session(id).flatMap(s->event(s,host,null,"GAME_STARTED")))
            .then(Mono.zip(view(id,host),games.view(room,host)).map(t->new Match(t.getT1(),t.getT2())))
            .onErrorResume(error->games.cancel(room).then(db.sql("UPDATE huud_sessions SET activity='waiting',current_room_id=NULL WHERE id=:id AND current_room_id=:room")
                .bind("id",id).bind("room",room).fetch().rowsUpdated()).then(Mono.error(error))));
    }
    public Mono<View> rematch(UUID id,UUID host) { return rematch(id,host,null); }
    public Mono<View> rematch(UUID id,UUID host,Integer version) {
        return change(id,host,true,s->{
            expected(s,version);
            if(!"results".equals(s.activity())) return Mono.error(ApiExceptions.conflict("finish the match before a rematch"));
            return selected(s).flatMap(roster->selectInside(s,s.gameType(),s.config()).thenMany(Flux.fromIterable(roster))
                .concatMap(u->db.sql("INSERT INTO huud_game_requests(huud_id,activity_version,user_id,status) SELECT :id,:version,:user,'selected' WHERE EXISTS(SELECT 1 FROM huud_members WHERE huud_id=:id AND user_id=:user AND status='participant')")
                    .bind("id",id).bind("version",s.version()+1).bind("user",u).fetch().rowsUpdated()).then(Mono.just(id)));
        }).flatMap(x->view(x,host));
    }
    public Mono<Void> leave(UUID id,UUID user) {
        return change(id,user,false,s->removeInside(s,user,user,false));
    }
    public Mono<View> remove(UUID id,UUID host,UUID target) {
        if(host.equals(target)) return Mono.error(ApiExceptions.badRequest("use Leave Huud or End Huud for yourself"));
        return change(id,host,true,s->removeInside(s,host,target,true).thenReturn(id)).flatMap(x->view(x,host));
    }
    public Mono<Void> mute(UUID id,UUID host,UUID target) {
        return change(id,host,true,s->access.requireParticipant(id,target)
            .then(games.muteVoice(id,target)).then(event(s,host,target,"MIC_MUTED")));
    }
    public Mono<View> removeFromGame(UUID id,UUID host,UUID target,Integer version) {
        return change(id,host,true,s->{
            expected(s,version);
            if("waiting".equals(s.activity())) return db.sql("UPDATE huud_game_requests SET status='not_selected' WHERE huud_id=:id AND activity_version=:version AND user_id=:target")
                .bind("id",id).bind("version",s.version()).bind("target",target).fetch().rowsUpdated()
                .then(event(s,host,target,"PLAYER_NOT_SELECTED")).thenReturn(id);
            if(!"playing".equals(s.activity())) return Mono.error(ApiExceptions.conflict("there is no current game seat to remove"));
            return selected(s).flatMap(roster->{
                if(!roster.contains(target)) return Mono.error(ApiExceptions.conflict("that participant is not playing"));
                return games.removePlayer(s.room(),target).then(event(s,host,target,"PLAYER_REMOVED")).thenReturn(id);
            });
        }).flatMap(x->view(x,host));
    }
    private Mono<Void> removeInside(Session s,UUID actor,UUID target,boolean banned) {
        // The current engine roster remains immutable; an active seat is forfeited/cancelled by the bridge.
        return ("playing".equals(s.activity()) && s.room()!=null?games.removePlayer(s.room(),target):Mono.<Void>empty())
            .then(db.sql("INSERT INTO huud_members(huud_id,user_id,status) VALUES(:id,:user,:status) ON CONFLICT(huud_id,user_id) DO UPDATE SET status=EXCLUDED.status")
                .bind("id",s.id()).bind("user",target).bind("status",banned?"banned":"left").fetch().rowsUpdated())
            .then(db.sql("UPDATE huud_game_requests SET status='not_selected' WHERE huud_id=:id AND activity_version=:version AND user_id=:user AND :waiting")
                .bind("id",s.id()).bind("version",s.version()).bind("user",target).bind("waiting",!"playing".equals(s.activity())).fetch().rowsUpdated())
            .then(db.sql("DELETE FROM huud_admission WHERE huud_id=:id AND user_id=:user AND :banned")
                .bind("id",s.id()).bind("user",target).bind("banned",banned).fetch().rowsUpdated())
            .then(stopViewing(s.id(),target)).then(games.removeVoice(s.id(),target))
            .then(event(s,actor,target,banned?"REMOVED":"LEFT"));
    }
    public Mono<Void> end(UUID id,UUID host) {
        return change(id,host,true,s->endInside(s,host,"ENDED"));
    }
    private Mono<Void> endInside(Session s,UUID actor,String reason) {
        return (s.room()==null?Mono.<Void>empty():games.cancel(s.room()))
            .then(games.endVoice(s.id()))
            .then(db.sql("UPDATE huud_sessions SET status='ended',ended_at=now() WHERE id=:id")
                .bind("id",s.id()).fetch().rowsUpdated())
            .then(db.sql("UPDATE huud_members SET status='left' WHERE huud_id=:id AND status='participant'").bind("id",s.id()).fetch().rowsUpdated())
            .then(event(s,actor,null,reason));
    }
    public Flux<ChatMessage> chat(UUID id,UUID user) {
        return access.requireView(id,user).thenMany(db.sql("""
            SELECT c.*,u.username,u.avatar_url FROM huud_messages c JOIN users u ON u.id=c.user_id
            WHERE c.huud_id=:id AND NOT EXISTS(SELECT 1 FROM user_blocks b WHERE b.blocker_id=:user AND b.blocked_id=c.user_id)
            ORDER BY c.created_at DESC LIMIT 100
            """).bind("id",id).bind("user",user).map((r,m)->new ChatMessage(r.get("id",UUID.class),r.get("user_id",UUID.class),
                r.get("username",String.class),r.get("avatar_url",String.class),r.get("text",String.class),r.get("created_at",Instant.class))).all());
    }
    public Mono<Void> send(UUID id,UUID user,String text) {
        if(text==null || text.isBlank() || text.length()>1000) return Mono.error(ApiExceptions.badRequest("message must be 1–1000 characters"));
        return change(id,user,false,s->access.requireParticipant(id,user).then(rate(user,"CHAT_SENT",12,10))
            .then(db.sql("INSERT INTO huud_messages(huud_id,user_id,text) VALUES(:id,:user,:text)").bind("id",id).bind("user",user).bind("text",text.strip()).fetch().rowsUpdated())
            .then(event(s,user,null,"CHAT_SENT")));
    }
    public Mono<Void> report(UUID id,UUID user,Report report) {
        return change(id,user,false,s->rate(user,"REPORTED",5,60)
            .then(report.messageId()==null?Mono.empty():db.sql("SELECT 1 AS found FROM huud_messages WHERE id=:message AND huud_id=:id AND user_id=:target")
                .bind("message",report.messageId()).bind("id",id).bind("target",report.userId()).fetch().one()
                .switchIfEmpty(Mono.error(ApiExceptions.badRequest("message does not belong to this user and Huud"))).then())
            .then(Mono.defer(()->{
                var q=db.sql("INSERT INTO huud_reports(huud_id,reporter_id,reported_user_id,room_id,message_id,reason) VALUES(:id,:user,:target,:room,:message,:reason)")
                    .bind("id",id).bind("user",user).bind("target",report.userId()).bind("reason",report.reason());
                q=s.room()==null?q.bindNull("room",UUID.class):q.bind("room",s.room());
                q=report.messageId()==null?q.bindNull("message",UUID.class):q.bind("message",report.messageId());
                return q.fetch().rowsUpdated().then(event(s,user,report.userId(),"REPORTED"));
            })));
    }
    public Mono<Void> block(UUID id,UUID user,UUID target) {
        if(user.equals(target)) return Mono.error(ApiExceptions.badRequest("cannot block yourself"));
        return change(id,user,false,s->db.sql("INSERT INTO user_blocks(blocker_id,blocked_id) VALUES(:user,:target) ON CONFLICT DO NOTHING")
            .bind("user",user).bind("target",target).fetch().rowsUpdated()
            .then(s.owner().equals(user)?removeInside(s,user,target,true):Mono.empty()).then(event(s,user,target,"BLOCKED")).then(games.recheckAccess(id)));
    }
    private Mono<Void> rate(UUID actor,String kind,int max,int seconds) {
        return lock("huud-rate:"+actor).then(db.sql("SELECT count(*)::int AS n FROM huud_events WHERE actor_id=:actor AND kind=:kind AND created_at>now()-(:seconds * interval '1 second')")
            .bind("actor",actor).bind("kind",kind).bind("seconds",seconds).map((r,m)->r.get("n",Integer.class)).one())
            .flatMap(n->n>=max?Mono.error(new org.springframework.web.server.ResponseStatusException(org.springframework.http.HttpStatus.TOO_MANY_REQUESTS,"slow down and try again shortly")):Mono.empty());
    }
    private Mono<Void> event(Session s,UUID actor,UUID target,String kind) { return event(s.id(),actor,target,s.room(),s.version(),kind); }
    private Mono<Void> event(UUID id,UUID actor,UUID target,UUID room,int version,String kind) {
        var q=db.sql("INSERT INTO huud_events(huud_id,actor_id,target_id,room_id,activity_version,kind) VALUES(:id,:actor,:target,:room,:version,:kind)")
            .bind("id",id).bind("version",version).bind("kind",kind);
        q=actor==null?q.bindNull("actor",UUID.class):q.bind("actor",actor);
        q=target==null?q.bindNull("target",UUID.class):q.bind("target",target);
        q=room==null?q.bindNull("room",UUID.class):q.bind("room",room);
        return q.fetch().rowsUpdated().then(db.sql("UPDATE huud_sessions SET last_activity_at=now() WHERE id=:id")
            .bind("id",id).fetch().rowsUpdated()).then();
    }
    public Mono<Void> expire() {
        return expirable(null).concatMap(id->tx.transactional(lock("huud:"+id)
            .thenMany(expirable(id)).next().flatMap(found->session(found))
            .flatMap(s->endInside(s,null,"EXPIRED")))).then();
    }
    private Flux<UUID> expirable(UUID id) {
        var q=db.sql("""
            SELECT h.id FROM huud_sessions h WHERE h.status='active'
              AND (:all OR h.id=:id)
              AND NOT EXISTS(SELECT 1 FROM huud_viewers v WHERE v.huud_id=h.id AND v.last_seen_at>now()-interval '90 seconds')
              AND (NOT EXISTS(SELECT 1 FROM huud_members m WHERE m.huud_id=h.id AND m.status='participant')
                OR (h.owner_seen_at < now()-(:grace * interval '1 second')
                  AND h.last_activity_at<now()-(:idle * interval '1 second')
                  AND NOT EXISTS(SELECT 1 FROM huud_members m WHERE m.huud_id=h.id AND m.status='participant' AND m.last_seen_at>now()-(:grace * interval '1 second'))))
            """).bind("all",id==null).bind("id",id==null?new UUID(0,0):id)
            .bind("grace",grace.toSeconds()).bind("idle",idle.toSeconds());
        return q.map((r,m)->r.get("id",UUID.class)).all();
    }
}
