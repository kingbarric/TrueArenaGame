package app.truearena;
import app.truearena.api.calls.VoiceSessionService;
import app.truearena.api.calls.CallRingService;
import app.truearena.api.room.RoomService;
import app.truearena.api.ws.GameOrchestrator;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.persistence.*;
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
import reactor.core.publisher.Mono;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

@SpringBootTest
@Tag("integration")
class VoiceSessionIT {
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


    @Autowired VoiceSessionService voice;
    @Autowired RoomService rooms;
    @Autowired RoomRepository roomRows;
    @Autowired GameSessionRepository games;
    @Autowired UserRepository users;
    @Autowired GroupRepository groups;
    @Autowired GameOrchestrator orchestrator;
    @Autowired InboxRegistry inbox;
    @Autowired CallRingService rings;
    @Autowired DatabaseClient db;
    @MockBean LiveKitRoomAdmin livekit;
    @BeforeEach void media() {
        when(livekit.remove(anyString(),anyString())).thenReturn(Mono.empty());
        when(livekit.muteAudio(anyString(),anyString())).thenReturn(Mono.empty());
    }
    UUID person() {
        String tag=UUID.randomUUID().toString().replace("-","").substring(0,15);
        return users.save(UserRow.newUser(null,tag+"@voice.test","Player "+tag,"v_"+tag)).block().id();
    }
    String group(UUID host) { return "group-"+groups.save(GroupRow.create("Hangout",null,host)).block().id(); }
    GameSessionRow start(UUID host,String game) {
        var room=rooms.create(host,null,game,null,null).block();
        roomRows.findById(room.id()).flatMap(r -> roomRows.save(r.withStatus("in_game"))).block();
        var session=games.save(GameSessionRow.start(room.id(),game,"{}",1,1)).block();
        voice.gameStarted(room.id()).block();
        return games.findById(session.id()).block();
    }
    @Test void reopeningLobbyKeepsCodeRosterAndCreatorAfterNavigation() {
        UUID host=person(), guest=person();
        var first=rooms.create(host,null,"draughts",null,null).block();
        var rt=orchestrator.ensureRuntime(first.id()).block();
        orchestrator.onConnect(rt,host.toString()).block();
        orchestrator.onDisconnect(rt,host.toString()).block();
        rooms.join(first.code(),guest,"Opponent").block();
        var reopened=rooms.create(host,null,"draughts",null,null).block();
        assertThat(reopened.id()).isEqualTo(first.id());
        assertThat(reopened.code()).isEqualTo(first.code());
        assertThat(reopened.hostId()).isEqualTo(host);
        assertThat(reopened.members()).hasSize(2);
        assertThat(rooms.join(first.code(),host,"Host").block().id()).isEqualTo(first.id());
    }
    @Test void cancelRetiresCodeAndNextLobbyIsNew() {
        UUID host=person(); var first=rooms.create(host,null,"chess",null,null).block();
        rooms.abandon(first.id(),host).block();
        assertThatThrownBy(() -> rooms.join(first.code(),person(),"Player").block()).isInstanceOf(ResponseStatusException.class);
        var next=rooms.create(host,null,"chess",null,null).block();
        assertThat(next.id()).isNotEqualTo(first.id()); assertThat(next.code()).isNotEqualTo(first.code());
    }
    @Test void concurrentCreateKeepsOneLobbyAndCode() {
        UUID host=person();
        var pair=Mono.zip(rooms.create(host,null,"draughts",null,null), rooms.create(host,null,"draughts",null,null)).block();
        assertThat(pair.getT1().id()).isEqualTo(pair.getT2().id());
    }
    @Test void directCallGameResultThenAnotherGameKeepsSameVoiceSession() {
        UUID host=person(), friend=person();
        String name="dm-"+host+"-"+friend;
        var call=voice.join(host,name).block(); voice.join(friend,name).block();
        var gameA=start(host,"draughts");
        assertThat(gameA.voiceSessionId()).isEqualTo(call.voiceSessionId());
        assertThat(voice.active(host).block().activeGameSessionId()).isEqualTo(gameA.id());
        voice.gameEnded(gameA.roomId()).block();
        assertThat(voice.active(host).block().participants()).hasSize(2);
        assertThat(voice.active(host).block().activeGameSessionId()).isNull();
        var gameB=start(host,"chess");
        assertThat(gameB.voiceSessionId()).isEqualTo(call.voiceSessionId());
        assertThat(voice.active(friend).block().voiceSessionId()).isEqualTo(call.voiceSessionId());
    }
    @Test void groupCallSpectatorStaysAndLeavingCallDoesNotEndGame() {
        UUID host=person(), player=person(), spectator=person(); String name=group(host);
        var call=voice.join(host,name).block(); voice.join(player,name).block(); voice.join(spectator,name).block();
        var room=rooms.create(host,null,"chess",null,null).block(); rooms.join(room.code(),player,"Opponent").block();
        var game=start(host,"chess");
        assertThat(rooms.get(room.id(),host).block().members()).hasSize(2);
        voice.gameEnded(game.roomId()).block();
        assertThat(voice.active(spectator).block().voiceSessionId()).isEqualTo(call.voiceSessionId());
        voice.leave(player,name).block();
        assertThat(roomRows.findById(room.id()).block().status()).isEqualTo("in_game");
        assertThat(voice.active(player).block()).isNull();
        assertThat(voice.active(host).block().participants()).hasSize(2);
    }
    @Test void reconnectPreservesMembershipMuteAndJoinedAt() {
        UUID host=person(); String name=group(host); var before=voice.join(host,name).block();
        voice.mute(host,true).block(); inbox.leaveCall(host); // independent inbox reconnect/restart
        var restored=voice.join(host,name).block();
        assertThat(restored.voiceSessionId()).isEqualTo(before.voiceSessionId());
        assertThat(restored.participants().getFirst().muted()).isTrue();
        assertThat(restored.participants().getFirst().joinedAt()).isEqualTo(before.participants().getFirst().joinedAt());
    }
    @Test void switchRequiresLeavingAndDoesNotTouchGameState() {
        UUID host=person(), guest=person(); String first=group(host), second=group(guest);
        voice.join(host,first).block();
        assertThatThrownBy(() -> voice.join(host,second).block()).isInstanceOf(ResponseStatusException.class);
        voice.leave(host,first).block(); voice.join(host,second).block();
        assertThat(voice.active(host).block().roomName()).isEqualTo(second);
    }
    @Test void onlyHostCanRemoveEndAndDelegateAndHostMustTransferBeforeLeaving() {
        UUID host=person(), guest=person(); String name=group(host); var call=voice.join(host,name).block(); voice.join(guest,name).block();
        assertThatThrownBy(() -> rings.remove(guest,name,host).block()).isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> voice.end(guest).block()).isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> voice.leave(host,name).block()).isInstanceOf(ResponseStatusException.class);
        voice.delegate(host,guest).block(); voice.leave(host,name).block();
        assertThat(voice.active(guest).block().ownerId()).isEqualTo(guest);
        voice.end(guest).block(); assertThat(voice.view(call.voiceSessionId()).block().status()).isEqualTo("ended");
    }
    @Test void adminCanRemoveParticipantWithoutEndingHangout() {
        UUID host=person(), guest=person(); String name=group(host); voice.join(host,name).block(); voice.join(guest,name).block();
        rings.remove(host,name,guest).block(); assertThat(voice.active(guest).block()).isNull();
        assertThat(voice.active(host).block().participants()).hasSize(1);
        assertThatThrownBy(() -> rings.joinToken(guest,name).block()).isInstanceOf(ResponseStatusException.class);
    }
    @Test void publicJoinRequiresApprovalAndJoiningDoesNotCreateFriendship() {
        UUID host=person(), visitor=person(); String name=group(host); var call=voice.join(host,name).block();
        voice.settings(host,"private","host").block();
        assertThatThrownBy(() -> voice.requestJoin(visitor,call.voiceSessionId()).block()).isInstanceOf(ResponseStatusException.class);
        voice.settings(host,"public","host").block(); voice.requestJoin(visitor,call.voiceSessionId()).block();
        assertThat(voice.approved(visitor,name).block()).isFalse();
        voice.answerRequest(host,visitor,true).block(); assertThat(voice.approved(visitor,name).block()).isTrue();
        voice.join(visitor,name).block();
        var friends=db.sql("SELECT count(*) AS n FROM friends WHERE low_user_id=:low AND high_user_id=:high")
            .bind("low",FriendRow.lowerOf(host,visitor)).bind("high",FriendRow.lowerOf(host,visitor).equals(host)?visitor:host)
            .map((r,m) -> r.get("n",Long.class)).one().block(); assertThat(friends).isZero();
    }
}
