package app.truearena;

import app.truearena.api.socialhuud.*;
import app.truearena.api.socialhuud.SocialHuudDtos.*;
import app.truearena.api.auth.JwtService;
import app.truearena.api.calls.*;
import app.truearena.api.room.RoomService;
import app.truearena.api.ws.GameOrchestrator;
import app.truearena.persistence.*;
import app.truearena.room.RoomRuntimeRegistry;
import app.truearena.voice.LiveKitRoomAdmin;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.web.server.ResponseStatusException;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import reactor.core.publisher.*;
import java.util.*;
import java.time.Duration;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

@SpringBootTest
@Tag("integration")
class SocialHuudIT {
    private static final boolean EXTERNAL = System.getProperty("it.r2dbc.url") != null;
    private static final PostgreSQLContainer<?> POSTGRES = EXTERNAL ? null : new PostgreSQLContainer<>("postgres:16");
    private static final GenericContainer<?> REDIS = EXTERNAL ? null
            : new GenericContainer<>("redis:7").withExposedPorts(6379);

    static {
        if (!EXTERNAL) {
            POSTGRES.start();
            REDIS.start();
        }
    }

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        if (EXTERNAL) {
            r.add("spring.r2dbc.url", () -> System.getProperty("it.r2dbc.url"));
            r.add("spring.r2dbc.username", () -> System.getProperty("it.db.user"));
            r.add("spring.r2dbc.password", () -> System.getProperty("it.db.password"));
            r.add("spring.flyway.url", () -> System.getProperty("it.jdbc.url"));
            r.add("spring.flyway.user", () -> System.getProperty("it.db.user"));
            r.add("spring.flyway.password", () -> System.getProperty("it.db.password"));
            r.add("spring.data.redis.host", () -> System.getProperty("it.redis.host", "localhost"));
            r.add("spring.data.redis.port", () -> System.getProperty("it.redis.port", "6379"));
            r.add("spring.data.redis.database", () -> System.getProperty("it.redis.database", "0"));
            return;
        }
        r.add("spring.r2dbc.url", () -> "r2dbc:postgresql://" + POSTGRES.getHost() + ":"
                + POSTGRES.getFirstMappedPort() + "/" + POSTGRES.getDatabaseName());
        r.add("spring.r2dbc.username", POSTGRES::getUsername);
        r.add("spring.r2dbc.password", POSTGRES::getPassword);
        r.add("spring.flyway.url", POSTGRES::getJdbcUrl);
        r.add("spring.flyway.user", POSTGRES::getUsername);
        r.add("spring.flyway.password", POSTGRES::getPassword);
        r.add("spring.data.redis.host", REDIS::getHost);
        r.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
    }


    @Autowired SocialHuudService huuds;
    @Autowired SocialHuudAccess access;
    @Autowired GameOrchestrator games;
    @Autowired RoomRuntimeRegistry runtimes;
    @Autowired UserRepository users;
    @Autowired DatabaseClient db;
    @Autowired JwtService jwt;
    @Autowired CallRingService calls;
    @Autowired VoiceSessionService voiceSessions;
    @Autowired RoomService rooms;
    @Autowired HuudTelemetry telemetry;
    @Autowired HuudGameBridge bridge;
    @Autowired com.fasterxml.jackson.databind.ObjectMapper mapper;
    @Autowired app.truearena.api.bot.BotService bots;
    @MockBean LiveKitRoomAdmin voice;

    @BeforeEach void voiceOffline() {
        when(voice.remove(anyString(),anyString())).thenReturn(Mono.empty());
        when(voice.setCanPublish(anyString(),anyString(),anyBoolean())).thenReturn(Mono.empty());
        when(voice.muteAudio(anyString(),anyString())).thenReturn(Mono.empty());
    }
    private UUID human() {
        String name="h_"+UUID.randomUUID().toString().replace("-","").substring(0,15);
        return users.save(UserRow.newUser(null,name+"@huud.test",name,name)).map(UserRow::id).block();
    }
    private View create(UUID owner,String type,String privacy) {
        return huuds.create(owner,new Create(null,privacy,null,type,null)).block();
    }
    private void join(View h,UUID player) {
        huuds.requestJoin(h.id(),player).block();
        huuds.answerJoin(h.id(),h.ownerId(),player,true).block();
    }
    private void select(View h,UUID player) {
        huuds.requestGame(h.id(),player).block();
        huuds.selectPlayer(h.id(),h.ownerId(),player,true).block();
    }
    private void denied(Runnable action) {
        assertThatThrownBy(action::run).isInstanceOf(ResponseStatusException.class);
    }
    @Test void oneOwnedSessionSurvivesGameTapsAndNavigationAndConcurrentCreation() {
        UUID host=human(), visitor=human();
        View h=create(host,"draughts","public");
        View other=create(visitor,"whot","public");
        huuds.heartbeat(other.id(),host).block();
        huuds.stopViewing(h.id(),host).block();
        List<View> attempts=Flux.range(0,8).flatMap(i->huuds.create(host,new Create("ignored","private",null,"whot",null)),8)
            .collectList().block();
        assertThat(attempts).allSatisfy(v->{ assertThat(v.id()).isEqualTo(h.id());assertThat(v.code()).isEqualTo(h.code());assertThat(v.gameType()).isEqualTo("draughts"); });
        assertThat(huuds.owned(host).block().id()).isEqualTo(h.id());
        assertThat(huuds.view(other.id(),visitor).block().gameType()).isEqualTo("whot");
    }
    @Test void oneAdmissionRequestGrantsMicButNeverAGameSeat() {
        UUID host=human(), viewer=human();
        View h=create(host,"draughts","public");
        huuds.heartbeat(h.id(),viewer).block();
        View requested=huuds.requestJoin(h.id(),viewer).block();
        assertThat(requested.participant()).isFalse();
        assertThat(requested.joinRequestStatus()).isEqualTo("requested");
        assertThat(requested.participantCount()).isEqualTo(1);
        assertThat(requested.viewerCount()).isEqualTo(1);
        denied(()->calls.joinToken(viewer,"huud-"+h.id()).block());
        denied(()->huuds.requestGame(h.id(),viewer).block());
        huuds.answerJoin(h.id(),host,viewer,true).block();
        View participant=huuds.view(h.id(),viewer).block();
        assertThat(participant.participant()).isTrue();
        assertThat(participant.participantCount()).isEqualTo(2);
        assertThat(participant.viewerCount()).isZero();
        assertThat(participant.selectedPlayers()).isEmpty();
        assertThat(calls.joinToken(viewer,"huud-"+h.id()).block().roomName()).isEqualTo("huud-"+h.id());
        assertThat(huuds.requestGame(h.id(),viewer).block().gameRequestStatus()).isEqualTo("requested");
        denied(()->huuds.start(h.id(),viewer).block());
    }
    @Test void completeDraughtsToWhotLoopKeepsHostAudienceCodeChatAndVoice() {
        UUID host=human(), a=human(), b=human(), viewer=human();
        View h=create(host,"draughts","public");
        join(h,a);join(h,b);
        huuds.heartbeat(h.id(),viewer).block();
        huuds.send(h.id(),a,"Stay for Whot!").block();
        VoiceSessionService.VoiceSession voiceSession=voiceSessions.join(a,"huud-"+h.id()).block();
        select(h,a);select(h,b);
        Match match=huuds.start(h.id(),host).block();
        assertThat(match.room().members()).extracting(m->m.userId()).containsExactlyInAnyOrder(a,b).doesNotContain(host);
        assertThat(match.huud().playerCount()).isEqualTo(2);
        assertThat(match.huud().participantCount()).isEqualTo(3);
        assertThat(match.huud().viewerCount()).isEqualTo(1);
        assertThat(runtimes.find(match.room().id()).orElseThrow().hostUserId).isEqualTo(host.toString());
        denied(()->huuds.requestGame(h.id(),a).block());
        denied(()->huuds.selectGame(h.id(),host,new Game("whot",null)).block());
        assertThat(create(host,"whot","public").currentRoomId()).isEqualTo(match.room().id());
        games.forfeitHuudPlayer(match.room().id(),a).block();
        assertThat(huuds.view(h.id(),host).block().activity()).isEqualTo("results");
        assertThat(huuds.view(h.id(),host).block().playerCount()).isZero();
        assertThat(voiceSessions.active(a).block().voiceSessionId()).isEqualTo(voiceSession.voiceSessionId());
        View whot=huuds.selectGame(h.id(),host,new Game("whot",null)).block();
        assertThat(whot.code()).isEqualTo(h.code());
        assertThat(whot.selectedPlayers()).isEmpty();
        select(whot,a);select(whot,b);
        Match cards=huuds.start(h.id(),host).block();
        assertThat(cards.room().id()).isNotEqualTo(match.room().id());
        assertThat(cards.huud().viewerCount()).isEqualTo(1);
        assertThat(huuds.chat(h.id(),viewer).collectList().block()).extracting(ChatMessage::text).contains("Stay for Whot!");
        var rt=runtimes.find(cards.room().id()).orElseThrow();
        assertThat(rt.module().broadcastState(rt.state()).data()).doesNotContainKeys("hands","yourHand");
        assertThat(games.authenticate(cards.room().id().toString(),jwt.issueAccess(viewer),true).block().spectator()).isTrue();
        assertThat(voiceSessions.active(a).block().roomName()).isEqualTo("huud-"+h.id());
    }

    @Test void privateAndFriendsAccessIsEnforcedOnRestSocketAndVoice() {
        UUID host=human(), outsider=human();
        View h=create(host,"draughts","private");
        denied(()->huuds.view(h.id(),outsider).block());
        assertThat(huuds.discover(outsider).collectList().block()).noneMatch(v->v.id().equals(h.id()));
        View invited=huuds.watchCode(outsider,h.code()).block();
        assertThat(invited.participant()).isFalse();
        denied(()->calls.joinToken(outsider,"huud-"+h.id()).block());
        join(h,outsider);
        huuds.remove(h.id(),host,outsider).block();
        denied(()->huuds.watchCode(outsider,h.code()).block());
        denied(()->huuds.requestJoin(h.id(),outsider).block());
        denied(()->calls.joinToken(outsider,"huud-"+h.id()).block());
        View friends=create(human(),"draughts","friends");
        denied(()->huuds.watchCode(outsider,friends.code()).block());
    }
    @Test void explicitEndCancelsMatchWithoutRatingAndInvalidatesCode() {
        UUID host=human(), a=human(), b=human();
        View h=create(host,"whot","public");join(h,a);join(h,b);select(h,a);select(h,b);
        Match match=huuds.start(h.id(),host).block();
        huuds.end(h.id(),host).block();
        assertThat(huuds.owned(host).block()).isNull();
        denied(()->huuds.watchCode(a,h.code()).block());
        denied(()->calls.joinToken(a,"huud-"+h.id()).block());
        assertThat(db.sql("SELECT count(*)::int AS n FROM match_records WHERE room_id=:room").bind("room",match.room().id())
            .map((r,m)->r.get("n",Integer.class)).one().block()).isZero();
        assertThat(runtimes.find(match.room().id()).orElseThrow().cancelled).isTrue();
        assertThat(create(host,null,"public").code()).isNotEqualTo(h.code());
    }
    @Test void rematchPreselectsOnlyRemainingMembersAndNonAdminCannotControlIt() {
        UUID host=human(), a=human(), b=human(), spectator=human();
        View h=create(host,"draughts","public");join(h,a);join(h,b);join(h,spectator);select(h,a);select(h,b);
        Match match=huuds.start(h.id(),host).block();
        games.forfeitHuudPlayer(match.room().id(),a).block();
        huuds.leave(h.id(),a).block();
        View rematch=huuds.rematch(h.id(),host).block();
        assertThat(rematch.selectedPlayers()).containsExactly(b);
        assertThat(rematch.activityVersion()).isGreaterThan(h.activityVersion());
        denied(()->huuds.selectPlayer(h.id(),spectator,spectator,true).block());
        denied(()->huuds.end(h.id(),spectator).block());
        denied(()->huuds.selectGame(h.id(),spectator,new Game("whot",null)).block());
    }
    @Test void reportContextAndChatRateLimitsAreDurable() {
        UUID host=human(), a=human();
        View h=create(host,null,"public");join(h,a);
        huuds.send(h.id(),a,"hello").block();
        ChatMessage message=huuds.chat(h.id(),host).collectList().block().getFirst();
        huuds.report(h.id(),host,new Report(a,"abuse",message.id())).block();
        denied(()->huuds.report(h.id(),host,new Report(a,"wrong context",UUID.randomUUID())).block());
        for(int i=0;i<11;i++) huuds.send(h.id(),a,"message "+i).block();
        assertThatThrownBy(()->huuds.send(h.id(),a,"spam").block()).isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("429");
        huuds.block(h.id(),host,a).block();
        denied(()->huuds.watchCode(a,h.code()).block());
    }
    @Test void delayedGameRequestsCannotApplyToANewActivity() {
        UUID host=human(), player=human();
        View h=create(host,"draughts","public");join(h,player);
        huuds.selectGame(h.id(),host,new Game("whot",null)).block();
        denied(()->huuds.requestGame(h.id(),player,h.activityVersion()).block());
        denied(()->huuds.selectPlayer(h.id(),host,player,true,h.activityVersion()).block());
        denied(()->huuds.start(h.id(),host,h.activityVersion()).block());
        assertThat(huuds.view(h.id(),player).block().gameRequestStatus()).isEqualTo("none");
    }
    @Test void switchingPrivacyRevokesExistingViewerSocketsAndRoomLookups() {
        UUID host=human(),a=human(),b=human(),viewer=human();
        View h=create(host,"draughts","public");join(h,a);join(h,b);select(h,a);select(h,b);
        Match match=huuds.start(h.id(),host).block();
        var rt=runtimes.find(match.room().id()).orElseThrow();
        games.onSpectatorConnect(rt,viewer.toString()).block();
        huuds.settings(h.id(),host,new Settings(h.name(),"private",null)).block();
        assertThat(rt.revokedUserIds).contains(viewer.toString());
        denied(()->rooms.get(match.room().id(),viewer).block());
        denied(()->games.authenticate(match.room().id().toString(),jwt.issueAccess(viewer),true).block());
        assertThat(games.authenticate(match.room().id().toString(),jwt.issueAccess(a),false).block()).isNotNull();
    }
    @Test void ownerCanLeaveVoiceWithoutTransferringHuudOwnership() {
        UUID host=human(),a=human();View h=create(host,null,"public");join(h,a);
        voiceSessions.join(host,"huud-"+h.id()).block();voiceSessions.join(a,"huud-"+h.id()).block();
        voiceSessions.leave(host,"huud-"+h.id()).block();
        assertThat(voiceSessions.active(a).block().ownerId()).isEqualTo(host);
        assertThat(huuds.owned(host).block().ownerId()).isEqualTo(host);
        assertThat(huuds.view(h.id(),a).block().participantCount()).isEqualTo(2);
    }

    @Test void reconnectGraceProtectsNavigationButInactiveAndEmptyHuudsEnd() {
        UUID host=human(),a=human();View h=create(host,null,"public");join(h,a);
        db.sql("UPDATE huud_sessions SET owner_seen_at=now()-interval '2 hours',last_activity_at=now()-interval '2 hours' WHERE id=:id")
            .bind("id",h.id()).fetch().rowsUpdated().block();
        huuds.expire().block();
        assertThat(huuds.view(h.id(),a).block().status()).isEqualTo("active");
        db.sql("UPDATE huud_members SET last_seen_at=now()-interval '2 hours' WHERE huud_id=:id")
            .bind("id",h.id()).fetch().rowsUpdated().block();
        huuds.presence(host).block(); // App navigation refreshes ownership independently of the viewed screen.
        huuds.expire().block();
        assertThat(huuds.owned(host).block()).isNotNull();
        db.sql("UPDATE huud_sessions SET owner_seen_at=now()-interval '2 hours',last_activity_at=now()-interval '2 hours' WHERE id=:id")
            .bind("id",h.id()).fetch().rowsUpdated().block();
        db.sql("UPDATE huud_members SET last_seen_at=now()-interval '2 hours' WHERE huud_id=:id")
            .bind("id",h.id()).fetch().rowsUpdated().block();
        huuds.expire().block();assertThat(huuds.owned(host).block()).isNull();
        View empty=create(host,null,"public");huuds.leave(empty.id(),host).block();
        huuds.expire().block();assertThat(huuds.owned(host).block()).isNull();
    }
    @Test void postGameRetentionSamplesMembersAndViewersSeparately() {
        UUID host=human(),a=human(),b=human(),viewer=human();View h=create(host,"draughts","public");
        join(h,a);join(h,b);select(h,a);select(h,b);huuds.heartbeat(h.id(),viewer).block();
        Match match=huuds.start(h.id(),host).block();games.forfeitHuudPlayer(match.room().id(),a).block();
        huuds.stopViewing(h.id(),viewer).block();huuds.leave(h.id(),a).block();
        db.sql("UPDATE huud_game_audience SET finished_at=now()-interval '1 minute' WHERE room_id=:room")
            .bind("room",match.room().id()).fetch().rowsUpdated().block();
        telemetry.sampleRetention().block();
        var audience=db.sql("SELECT user_id,population,retained FROM huud_game_audience WHERE room_id=:room")
            .bind("room",match.room().id()).fetch().all().collectList().block();
        assertThat(audience).hasSize(4);
        assertThat(audience).anySatisfy(row->{assertThat(row.get("user_id")).isEqualTo(viewer);assertThat(row.get("population")).isEqualTo("viewer");assertThat(row.get("retained")).isEqualTo(false);});
        assertThat(audience).anySatisfy(row->{assertThat(row.get("user_id")).isEqualTo(b);assertThat(row.get("retained")).isEqualTo(true);});
    }
    @Test void concurrentStartsCannotCreateTwoMatchesAndLegacyEndpointsCannotAlterRoster() {
        UUID host=human(),a=human(),b=human();View h=create(host,"draughts","public");join(h,a);join(h,b);select(h,a);select(h,b);
        huuds.selectPlayer(h.id(),host,a,false).block();huuds.selectPlayer(h.id(),host,a,true).block();
        var starts=Flux.range(0,2).flatMap(i->huuds.start(h.id(),host).materialize(),2).collectList().block();
        assertThat(starts.stream().filter(signal->signal.isOnNext()).count()).isEqualTo(1);
        Match match=starts.stream().filter(signal->signal.isOnNext()).findFirst().orElseThrow().get();
        denied(()->rooms.join(match.room().code(),human(),"intruder").block());
        denied(()->rooms.playTogether(host,match.room().id()).block());
        denied(()->rooms.abandon(match.room().id(),host).block());
        denied(()->bots.addBot(match.room().id(),host,"bot","easy").block());
    }
    @Test void voiceOutageDoesNotUndoRemovalAndIsRetried() {
        UUID host=human(),a=human();View h=create(host,null,"public");join(h,a);
        voiceSessions.join(a,"huud-"+h.id()).block();
        when(voice.remove("huud-"+h.id(),a.toString())).thenReturn(Mono.error(new IllegalStateException("offline")));
        huuds.remove(h.id(),host,a).block();
        denied(()->calls.joinToken(a,"huud-"+h.id()).block());
        assertThat(db.sql("SELECT count(*)::int AS n FROM huud_voice_revocations WHERE huud_id=:id")
            .bind("id",h.id()).map((r,m)->r.get("n",Integer.class)).one().block()).isEqualTo(1);
        when(voice.remove("huud-"+h.id(),a.toString())).thenReturn(Mono.empty());bridge.retryVoiceRevocations().block();
        assertThat(db.sql("SELECT count(*)::int AS n FROM huud_voice_revocations WHERE huud_id=:id")
            .bind("id",h.id()).map((r,m)->r.get("n",Integer.class)).one().block()).isZero();
    }
    @Test void removedPlayerBecomesSpectatorWithoutLosingHuudVoiceAndChat() {
        UUID host=human(),a=human(),b=human(),c=human();View h=create(host,"whot","public");
        join(h,a);join(h,b);join(h,c);select(h,a);select(h,b);select(h,c);
        Match match=huuds.start(h.id(),host).block();
        View removed=huuds.removeFromGame(h.id(),host,a,h.activityVersion()).block();
        assertThat(removed.selectedPlayers()).doesNotContain(a);
        assertThat(removed.participantCount()).isEqualTo(4);
        assertThat(huuds.view(h.id(),a).block().participant()).isTrue();
        denied(()->games.authenticate(match.room().id().toString(),jwt.issueAccess(a),false).block());
        assertThat(games.authenticate(match.room().id().toString(),jwt.issueAccess(a),true).block().spectator()).isTrue();
        assertThat(calls.joinToken(a,"huud-"+h.id()).block()).isNotNull();
        huuds.send(h.id(),a,"I’m still here").block();
    }
    @Test void hostCanModerateTraitorsWhileWatchingOnlyPublicState() throws Exception {
        UUID host=human(),viewer=human();View h=create(host,"truearena","public");
        for(int i=0;i<h.capacity().min();i++) {UUID player=human();join(h,player);select(h,player);}
        Match match=huuds.start(h.id(),host).block();var rt=runtimes.find(match.room().id()).orElseThrow();
        assertThat(rt.module().broadcastState(rt.state()).data()).doesNotContainKeys("yourRole","roles","nightPicks","fellowTraitors");
        String advance=mapper.writeValueAsString(app.truearena.ws.contract.Envelope.of(app.truearena.ws.contract.MessageType.PLAYER_ACTION,
            Map.of("action","ADVANCE_PHASE","data",Map.of())));
        games.handleFrame(rt,viewer.toString(),advance,true).block();assertThat(rt.state().phase()).isEqualTo("RoleReveal");
        games.handleFrame(rt,host.toString(),advance,true).block();assertThat(rt.state().phase()).isEqualTo("Night");
        assertThat(rt.module().broadcastState(rt.state()).data()).doesNotContainKeys("yourRole","roles","nightPicks","fellowTraitors");
    }
    @Test void banningAPendingViewerAlsoPreventsImmediateRejoining() {
        UUID host=human(),viewer=human();View h=create(host,null,"public");huuds.requestJoin(h.id(),viewer).block();
        huuds.remove(h.id(),host,viewer).block();
        denied(()->huuds.watchCode(viewer,h.code()).block());
        denied(()->huuds.requestJoin(h.id(),viewer).block());
        assertThat(huuds.view(h.id(),host).block().joinRequests()).isEmpty();
    }
}
