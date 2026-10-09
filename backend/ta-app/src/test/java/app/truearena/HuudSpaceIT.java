package app.truearena;
import app.truearena.api.huudspace.HuudSpaceAccess;
import app.truearena.api.huudspace.HuudSpaceService;
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
class HuudSpaceIT {
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


    @Autowired HuudSpaceService huuds;
    @Autowired HuudSpaceAccess access;
    @Autowired UserRepository users;
    @Autowired FriendRepository friendRows;
    @Autowired DatabaseClient db;
    @MockBean LiveKitRoomAdmin livekit;

    @BeforeEach void media() {
        when(livekit.remove(anyString(), anyString())).thenReturn(Mono.empty());
    }

    UUID person(String name) {
        String tag = UUID.randomUUID().toString().replace("-", "").substring(0, 15);
        return users.save(UserRow.newUser(null, tag + "@huud.test", name, "h_" + tag)).block().id();
    }

    UUID guest(String name) {
        String tag = UUID.randomUUID().toString().replace("-", "").substring(0, 15);
        return users.save(UserRow.newGuest("device-" + tag, name, "g_" + tag)).block().id();
    }

    void befriend(UUID a, UUID b) {
        friendRows.save(FriendRow.requested(a, b).accepted()).block();
    }

    /** Pretend {@code user}'s app went quiet that long ago. */
    void quiet(UUID huud, UUID user, String interval) {
        db.sql("UPDATE huud_space_members SET last_seen_at=now() - interval '" + interval + "' "
                + "WHERE huud_space_id=:id AND user_id=:user").bind("id", huud).bind("user", user)
                .fetch().rowsUpdated().block();
    }

    @Test void createDefaultsToFriendsAndANameAndReopensInsteadOfDuplicating() {
        UUID ada = person("Ada Obi");
        var first = huuds.create(ada, null, null).block();
        assertThat(first.name()).isEqualTo("Ada's Huud");
        assertThat(first.privacy()).isEqualTo("friends");
        assertThat(first.code()).hasSize(6).doesNotContain("0", "O", "1", "I", "L");
        assertThat(first.youAreHost()).isTrue();
        assertThat(first.members()).extracting("userId").containsExactly(ada);

        var again = huuds.create(ada, "Another one", "public").block();
        assertThat(again.id()).isEqualTo(first.id());
        assertThat(again.code()).isEqualTo(first.code());
        assertThat(huuds.current(ada).block().id()).isEqualTo(first.id());
    }

    @Test void guestsCanJoinButNotMakeAHuud() {
        UUID kid = guest("Guest");
        assertThatThrownBy(() -> huuds.create(kid, null, null).block()).isInstanceOf(ResponseStatusException.class);
        var huud = huuds.create(person("Host"), null, null).block();
        assertThat(huuds.joinByCode(kid, huud.code().toLowerCase()).block().youAreIn()).isTrue();
    }

    @Test void privacyDecidesWhoCanFindAHuudButTheCodeAlwaysWorks() {
        UUID host = person("Host"), friend = person("Friend"), stranger = person("Stranger");
        befriend(host, friend);
        var huud = huuds.create(host, "Friends only", "friends").block();

        assertThat(huuds.live(friend).collectList().block()).extracting("id").contains(huud.id());
        assertThat(huuds.live(stranger).collectList().block()).extracting("id").doesNotContain(huud.id());
        assertThatThrownBy(() -> huuds.join(stranger, huud.id()).block()).isInstanceOf(ResponseStatusException.class);
        // Looking in from Live shows the Huud but never its code.
        assertThat(huuds.view(huud.id(), friend).block().code()).isNull();

        assertThat(huuds.join(friend, huud.id()).block().code()).isEqualTo(huud.code());
        assertThat(huuds.joinByCode(stranger, huud.code()).block().members()).hasSize(3);

        var open = huuds.create(person("Public host"), null, "public").block();
        assertThat(huuds.live(stranger).collectList().block()).extracting("id").contains(open.id());
    }

    @Test void aLeavingHostHandsTheHuudToTheNextJoinerSkippingGuests() {
        UUID host = person("Host"), guestKid = guest("Guest"), second = person("Second"), third = person("Third");
        var huud = huuds.create(host, null, null).block();
        huuds.joinByCode(guestKid, huud.code()).block();
        huuds.joinByCode(second, huud.code()).block();
        huuds.joinByCode(third, huud.code()).block();

        huuds.leave(host, huud.id()).block();

        var after = huuds.view(huud.id(), third).block();
        assertThat(after.host().userId()).isEqualTo(second);
        assertThat(after.code()).isEqualTo(huud.code());
        assertThat(after.members()).extracting("userId").doesNotContain(host);
        assertThat(huuds.current(second).block().id()).isEqualTo(huud.id());
        // The old host is free to make a new one.
        assertThat(huuds.create(host, null, null).block().id()).isNotEqualTo(huud.id());
    }

    @Test void aHostWhoseAppWentQuietIsReplacedByTheNextJoiner() {
        UUID host = person("Host"), second = person("Second"), third = person("Third");
        var huud = huuds.create(host, null, null).block();
        huuds.joinByCode(second, huud.code()).block();
        huuds.joinByCode(third, huud.code()).block();

        quiet(huud.id(), host, "4 minutes");
        huuds.expire().block();
        assertThat(huuds.view(huud.id(), third).block().host().userId()).isEqualTo(host);

        quiet(huud.id(), host, "6 minutes");
        huuds.expire().block();
        var after = huuds.view(huud.id(), third).block();
        assertThat(after.host().userId()).isEqualTo(second);
        // Quiet but not gone yet: still listed until the member timeout.
        assertThat(after.members()).extracting("userId").contains(host);
    }

    @Test void someoneWhoLeftAndCameBackGoesToTheEndOfTheHostLine() {
        UUID host = person("Host"), early = person("Early"), late = person("Late");
        var huud = huuds.create(host, null, null).block();
        huuds.joinByCode(early, huud.code()).block();
        huuds.joinByCode(late, huud.code()).block();
        huuds.leave(early, huud.id()).block();
        huuds.joinByCode(early, huud.code()).block();

        huuds.leave(host, huud.id()).block();
        assertThat(huuds.view(huud.id(), early).block().host().userId()).isEqualTo(late);
    }

    @Test void theLastPersonLeavingEndsTheHuudAndItStaysInEveryonesHistory() {
        UUID host = person("Host"), friend = person("Friend");
        var huud = huuds.create(host, "Saturday", null).block();
        huuds.joinByCode(friend, huud.code()).block();
        huuds.leave(friend, huud.id()).block();
        huuds.leave(host, huud.id()).block();

        assertThat(huuds.current(host).block()).isNull();
        assertThatThrownBy(() -> huuds.joinByCode(person("Late"), huud.code()).block())
                .isInstanceOf(ResponseStatusException.class);
        for (UUID who : new UUID[]{host, friend}) {
            var history = huuds.history(who).collectList().block();
            assertThat(history).hasSize(1);
            assertThat(history.get(0).status()).isEqualTo("ended");
            assertThat(history.get(0).name()).isEqualTo("Saturday");
            assertThat(history.get(0).participants()).extracting("userId").containsExactlyInAnyOrder(host, friend);
        }
        assertThat(huuds.history(host).collectList().block().get(0).youCreated()).isTrue();
        assertThat(huuds.history(friend).collectList().block().get(0).youCreated()).isFalse();
    }

    @Test void membersWhoVanishAreDroppedAndAnEmptyHuudEnds() {
        UUID host = person("Host"), friend = person("Friend");
        var huud = huuds.create(host, null, null).block();
        huuds.joinByCode(friend, huud.code()).block();
        quiet(huud.id(), host, "11 minutes");
        quiet(huud.id(), friend, "11 minutes");
        huuds.expire().block();
        assertThat(huuds.history(host).collectList().block().get(0).status()).isEqualTo("ended");
        assertThat(huuds.current(host).block()).isNull();
    }

    @Test void aHuudNobodyCameToAndNothingWasPlayedInStaysOutOfHistory() {
        UUID host = person("Host");
        var lonely = huuds.create(host, null, null).block();
        assertThat(huuds.history(host).collectList().block()).extracting("id").containsExactly(lonely.id());
        huuds.end(host, lonely.id()).block();
        assertThat(huuds.history(host).collectList().block()).isEmpty();

        var played = huuds.create(host, null, null).block();
        var room = huuds.addGame(host, played.id(), "draughts").block();
        db.sql("INSERT INTO game_sessions(room_id,game_type,config,catalog_version,rng_seed) "
                + "VALUES(:room,'draughts','{}',1,1)").bind("room", room.id()).fetch().rowsUpdated().block();
        db.sql("UPDATE rooms SET status='ended' WHERE id=:id").bind("id", room.id()).fetch().rowsUpdated().block();
        huuds.end(host, played.id()).block();
        assertThat(huuds.history(host).collectList().block()).extracting("id").containsExactly(played.id());
    }

    @Test void endingClosesTheHuudForEveryoneAndOnlyTheHostCanEnd() {
        UUID host = person("Host"), friend = person("Friend");
        var huud = huuds.create(host, null, null).block();
        huuds.joinByCode(friend, huud.code()).block();
        assertThatThrownBy(() -> huuds.end(friend, huud.id()).block()).isInstanceOf(ResponseStatusException.class);
        huuds.end(host, huud.id()).block();
        var ended = huuds.view(huud.id(), friend).block();
        assertThat(ended.status()).isEqualTo("ended");
        assertThat(ended.youAreIn()).isFalse();
        assertThat(ended.code()).isNull();
        assertThat(access.canTalk(friend, ended.voiceRoom()).block()).isFalse();
    }

    @Test void someoneRemovedCannotComeBackOrTalk() {
        UUID host = person("Host"), rude = person("Rude");
        var huud = huuds.create(host, null, "public").block();
        huuds.joinByCode(rude, huud.code()).block();
        assertThat(access.canTalk(rude, huud.voiceRoom()).block()).isTrue();

        huuds.remove(host, huud.id(), rude).block();
        assertThat(access.canTalk(rude, huud.voiceRoom()).block()).isFalse();
        assertThatThrownBy(() -> huuds.joinByCode(rude, huud.code()).block()).isInstanceOf(ResponseStatusException.class);
        assertThat(huuds.live(rude).collectList().block()).extracting("id").doesNotContain(huud.id());
        assertThat(huuds.history(rude).collectList().block()).isEmpty();
    }

    @Test void oneGameAtATimeAndTheHuudOutlivesIt() {
        UUID host = person("Host"), friend = person("Friend");
        var huud = huuds.create(host, null, null).block();
        huuds.joinByCode(friend, huud.code()).block();
        assertThatThrownBy(() -> huuds.addGame(friend, huud.id(), "draughts").block())
                .isInstanceOf(ResponseStatusException.class);

        var room = huuds.addGame(host, huud.id(), "draughts").block();
        var withGame = huuds.view(huud.id(), friend).block();
        assertThat(withGame.currentGame().roomId()).isEqualTo(room.id());
        assertThat(withGame.currentGame().status()).isEqualTo("waiting");
        assertThatThrownBy(() -> huuds.addGame(host, huud.id(), "chess").block())
                .isInstanceOf(ResponseStatusException.class);

        db.sql("UPDATE rooms SET status='ended' WHERE id=:id").bind("id", room.id()).fetch().rowsUpdated().block();
        assertThat(huuds.view(huud.id(), friend).block().currentGame().status()).isEqualTo("finished");
        var next = huuds.addGame(host, huud.id(), "chess").block();
        assertThat(next.id()).isNotEqualTo(room.id());
        assertThat(huuds.view(huud.id(), friend).block().members()).hasSize(2);

        assertThat(huuds.clearGame(host, huud.id()).block().currentGame()).isNull();
    }
}
