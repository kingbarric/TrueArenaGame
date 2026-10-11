package app.truearena;

import app.truearena.api.huudspace.HuudSpaceService;
import app.truearena.api.huudspace.HuudSpaceChatService;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.room.RoomRuntime;
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
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;
import java.util.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

/** Real persistence plus independent app/game/media presence: don't end an active Huud. */
@SpringBootTest
@Tag("integration")
class HuudLifecycleIT {
    private static final boolean EXTERNAL = System.getProperty("it.r2dbc.url") != null;
    private static final PostgreSQLContainer<?> POSTGRES = EXTERNAL ? null : new PostgreSQLContainer<>("postgres:16");
    private static final GenericContainer<?> REDIS = EXTERNAL ? null : new GenericContainer<>("redis:7").withExposedPorts(6379);
    static { if (!EXTERNAL) { POSTGRES.start(); REDIS.start(); } }
    @DynamicPropertySource static void props(DynamicPropertyRegistry r) {
        r.add("spring.r2dbc.url", () -> EXTERNAL ? System.getProperty("it.r2dbc.url")
                : "r2dbc:postgresql://" + POSTGRES.getHost() + ":" + POSTGRES.getFirstMappedPort() + "/" + POSTGRES.getDatabaseName());
        r.add("spring.r2dbc.username", () -> EXTERNAL ? System.getProperty("it.db.user") : POSTGRES.getUsername());
        r.add("spring.r2dbc.password", () -> EXTERNAL ? System.getProperty("it.db.password") : POSTGRES.getPassword());
        r.add("spring.flyway.url", () -> EXTERNAL ? System.getProperty("it.jdbc.url") : POSTGRES.getJdbcUrl());
        r.add("spring.flyway.user", () -> EXTERNAL ? System.getProperty("it.db.user") : POSTGRES.getUsername());
        r.add("spring.flyway.password", () -> EXTERNAL ? System.getProperty("it.db.password") : POSTGRES.getPassword());
        r.add("spring.data.redis.host", () -> EXTERNAL ? System.getProperty("it.redis.host", "localhost") : REDIS.getHost());
        r.add("spring.data.redis.port", () -> EXTERNAL ? System.getProperty("it.redis.port", "6379") : REDIS.getMappedPort(6379));
    }
    @Autowired HuudSpaceService huuds;
    @Autowired HuudSpaceChatService chat;
    @Autowired UserRepository users;
    @Autowired DatabaseClient db;
    @Autowired InboxRegistry inbox;
    @Autowired RoomRuntimeRegistry runtimes;
    @MockBean LiveKitRoomAdmin livekit;
    final Map<UUID, UUID> spaces = new LinkedHashMap<>();
    final Map<UUID, Sinks.Many<Object>> sockets = new HashMap<>();
    final List<UUID> gameRooms = new ArrayList<>();

    @BeforeEach void media() {
        when(livekit.remove(anyString(), anyString())).thenReturn(Mono.empty());
        when(livekit.setCanPublish(anyString(), anyString(), anyBoolean())).thenReturn(Mono.empty());
        when(livekit.participantIds(anyString())).thenReturn(Mono.just(Set.of()));
    }
    @AfterEach void tidy() {
        sockets.forEach(inbox::disconnect);
        gameRooms.forEach(runtimes::remove);
        spaces.forEach((id, owner) -> { if (live(id)) huuds.endLive(owner, id).block(); });
    }
    UUID person() {
        String tag = UUID.randomUUID().toString().replace("-", "").substring(0, 15);
        return users.save(UserRow.newUser(null, tag + "@lifecycle.test", "Player", "l_" + tag)).block().id();
    }
    UUID make(UUID owner) {
        UUID id = huuds.create(owner, "Lifecycle", "public").block().id();
        spaces.put(id, owner);
        return id;
    }
    boolean live(UUID id) {
        return db.sql("SELECT live_since IS NOT NULL AS live FROM huud_spaces WHERE id=:id").bind("id", id)
                .map((r, m) -> r.get("live", Boolean.class)).one().block();
    }
    void age(UUID id, String interval) {
        db.sql("UPDATE huud_spaces SET live_since=now() - interval '" + interval + "' WHERE id=:id").bind("id", id).fetch().rowsUpdated().block();
        db.sql("UPDATE huud_space_members SET last_seen_at=now() - interval '" + interval + "' WHERE huud_space_id=:id").bind("id", id).fetch().rowsUpdated().block();
        db.sql("UPDATE rooms SET created_at=now() - interval '" + interval + "' WHERE huud_space_id=:id").bind("id", id).fetch().rowsUpdated().block();
    }
    UUID game(UUID owner, UUID id) {
        UUID room = huuds.addGame(owner, id, "draughts").block().id();
        gameRooms.add(room);
        return room;
    }

    @Test void aTemporaryHostCanOrganiseButCannotEndOrDeleteSomeoneElsesHuud() {
        UUID owner = person(), second = person();
        UUID id = make(owner);
        huuds.join(second, id).block();
        db.sql("UPDATE huud_space_members SET last_seen_at=now()-interval '6 minutes' WHERE huud_space_id=:id AND user_id=:user")
                .bind("id", id).bind("user", owner).fetch().rowsUpdated().block();
        huuds.expire().block();
        var cover = huuds.view(id, second).block();
        assertThat(cover.youAreHost()).isTrue();
        assertThat(cover.youOwn()).isFalse();
        assertThat(huuds.addGame(second, id, "chess").block()).isNotNull();
        assertThatThrownBy(() -> huuds.endLive(second, id).block()).isInstanceOf(ResponseStatusException.class)
                .satisfies(e -> assertThat(((ResponseStatusException)e).getStatusCode().value()).isEqualTo(403));
        assertThatThrownBy(() -> huuds.delete(second, id).block()).isInstanceOf(ResponseStatusException.class);
        assertThat(live(id)).isTrue();
        assertThat(huuds.endLive(owner, id).block().live()).isFalse();
    }

    @Test void anEmptyHuudDoesNotEndBefore24Hours() {
        UUID owner = person(), id = make(owner);
        game(owner, id);
        age(id, "23 hours 59 minutes");
        huuds.expire().block();
        assertThat(live(id)).isTrue();
    }

    @Test void after24HoursAnEmptyHuudEndsLiveAndCancelsItsWaitingGameButKeepsItsIdentityAndChat() {
        UUID owner = person(), id = make(owner);
        String code = huuds.view(id, owner).block().code();
        UUID room = game(owner, id);
        chat.send(owner, id, "See you tomorrow").block();
        age(id, "25 hours");
        db.sql("UPDATE huud_space_messages SET created_at=now()-interval '25 hours' WHERE huud_space_id=:id").bind("id", id).fetch().rowsUpdated().block();
        huuds.expire().block();
        assertThat(live(id)).isFalse();
        var after = huuds.view(id, owner).block();
        assertThat(after.code()).isEqualTo(code);
        assertThat(after.status()).isEqualTo("active");
        assertThat(chat.messages(owner, id, null).collectList().block()).extracting("body").containsExactly("See you tomorrow");
        assertThat(db.sql("SELECT count(*) AS n FROM rooms WHERE id=:id").bind("id", room)
                .map((r, m) -> ((Number)r.get("n")).intValue()).one().block()).isZero();
    }

    @Test void aRecentViewerKeepsAnOtherwiseEmptyHuudAlive() {
        UUID owner = person(), id = make(owner);
        age(id, "25 hours");
        huuds.watch(person(), id).block();
        huuds.expire().block();
        assertThat(live(id)).isTrue();
    }

    @Test void browsingElsewhereOrReturningAfterPresenceWasClearedRestartsThe24HourWindow() {
        UUID owner = person(), id = make(owner);
        age(id, "25 hours");
        db.sql("UPDATE huud_space_members SET live_at=NULL WHERE huud_space_id=:id").bind("id", id).fetch().rowsUpdated().block();
        huuds.heartbeat(owner).block();
        huuds.expire().block();
        assertThat(live(id)).isTrue();
    }

    @Test void anOnlineMemberWithAStaleHeartbeatKeepsTheHuudAlive() {
        UUID owner = person(), id = make(owner);
        age(id, "25 hours");
        var sink = Sinks.many().unicast().onBackpressureBuffer();
        sockets.put(owner, sink);
        inbox.connect(owner, sink);
        huuds.expire().block();
        assertThat(live(id)).isTrue();
        inbox.disconnect(owner, sink);
        sockets.clear();
        // The 24-hour clock starts from this activity, not from the original creation time.
        huuds.expire().block();
        assertThat(live(id)).isTrue();
    }

    @Test void connectedGamePlayersAndSpectatorsKeepTheHuudAliveWithoutAppHeartbeats() {
        for (boolean spectator : List.of(false, true)) {
            UUID owner = person(), id = make(owner), room = game(owner, id), user = person();
            age(id, "25 hours");
            RoomRuntime rt = runtimes.computeIfAbsent(room, key -> new RoomRuntime(key, owner.toString()));
            (spectator ? rt.spectatorUserIds : rt.connectedUserIds).add(user.toString());
            huuds.expire().block();
            assertThat(live(id)).isTrue();
            runtimes.remove(room);
        }
    }

    @Test void anActuallyConnectedVoiceListenerKeepsTheHuudAliveAndIsNotRemoved() {
        UUID owner = person(), id = make(owner);
        age(id, "25 hours");
        when(livekit.participantIds("huud-" + id)).thenReturn(Mono.just(Set.of(owner.toString())));
        huuds.expire().block();
        assertThat(live(id)).isTrue();
        verify(livekit, never()).remove("huud-" + id, owner.toString());
    }

    @Test void uncertainVoicePresenceNeverEndsTheHuud() {
        UUID owner = person(), id = make(owner);
        age(id, "25 hours");
        when(livekit.participantIds("huud-" + id)).thenReturn(Mono.error(new IllegalStateException("media unavailable")));
        assertThatThrownBy(() -> huuds.expire().block()).hasMessageContaining("media unavailable");
        assertThat(live(id)).isTrue();
    }

    @Test void aRecentChatMessageKeepsTheHuudAlive() {
        UUID owner = person(), id = make(owner);
        age(id, "25 hours");
        chat.send(owner, id, "Still here").block();
        huuds.expire().block();
        assertThat(live(id)).isTrue();
    }

    @Test void recentGameActivityProtectsTheHuudButACompletelyAbandonedGameIsClosedWithoutAWinner() {
        UUID owner = person(), id = make(owner), room = game(owner, id);
        age(id, "25 hours");
        db.sql("UPDATE rooms SET status='in_game' WHERE id=:room").bind("room", room).fetch().rowsUpdated().block();
        UUID session = db.sql("INSERT INTO game_sessions(room_id,game_type,config,catalog_version,rng_seed,started_at) "
                        + "VALUES(:room,'draughts','{}',1,1,now()-interval '25 hours') RETURNING id")
                .bind("room", room).map((r, m) -> r.get("id", UUID.class)).one().block();
        db.sql("INSERT INTO game_events(game_session_id,seq,type,payload,visibility_scope) VALUES(:id,1,'MOVE','{}','public')")
                .bind("id", session).fetch().rowsUpdated().block();
        huuds.expire().block();
        assertThat(live(id)).isTrue();
        db.sql("UPDATE game_events SET created_at=now()-interval '25 hours' WHERE game_session_id=:id")
                .bind("id", session).fetch().rowsUpdated().block();
        huuds.expire().block();
        assertThat(live(id)).isFalse();
        assertThat(db.sql("SELECT status FROM rooms WHERE id=:id").bind("id", room)
                .map((r, m) -> r.get("status", String.class)).one().block()).isEqualTo("ended");
        assertThat(db.sql("SELECT ended_at IS NOT NULL AS ended FROM game_sessions WHERE id=:id").bind("id", session)
                .map((r, m) -> r.get("ended", Boolean.class)).one().block()).isTrue();
        assertThat(db.sql("SELECT count(*) AS n FROM game_results WHERE game_session_id=:id").bind("id", session)
                .map((r, m) -> ((Number)r.get("n")).intValue()).one().block()).isZero();
    }
}
