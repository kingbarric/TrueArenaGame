package app.truearena;
import app.truearena.api.huudspace.HuudSpaceAccess;
import app.truearena.api.huudspace.HuudSpaceService;
import app.truearena.api.huudspace.HuudSpaceRequestService;
import app.truearena.api.huudspace.HuudSpaceChatService;
import app.truearena.api.huud.HuudDtos;
import app.truearena.api.huud.HuudService;
import app.truearena.api.safety.SafetyService;
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
    @Autowired HuudSpaceRequestService requests;
    @Autowired HuudSpaceChatService chat;
    @Autowired SafetyService safety;
    @Autowired HuudService feed;
    @Autowired HuudSpaceAccess access;
    @Autowired UserRepository users;
    @Autowired FriendRepository friendRows;
    @Autowired DatabaseClient db;
    @MockBean LiveKitRoomAdmin livekit;

    @BeforeEach void media() {
        when(livekit.remove(anyString(), anyString())).thenReturn(Mono.empty());
        when(livekit.setCanPublish(anyString(), anyString(), anyBoolean())).thenReturn(Mono.empty());
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
        var huud = huuds.create(person("Host"), null, "public").block();
        assertThat(huuds.joinByCode(kid, huud.code().toLowerCase()).block().youAreIn()).isTrue();
    }

    @Test void friendsWalkIntoAFriendsHuudAndEveryoneElseAsks() {
        UUID host = person("Host"), friend = person("Friend"), stranger = person("Stranger");
        befriend(host, friend);
        var huud = huuds.create(host, "Friends only", "friends").block();

        assertThat(huuds.live(friend).collectList().block()).extracting("id").contains(huud.id());
        assertThat(huuds.live(stranger).collectList().block()).extracting("id").doesNotContain(huud.id());
        // Looking in from Live shows the Huud but never its code.
        assertThat(huuds.view(huud.id(), friend).block().code()).isNull();
        assertThat(huuds.join(friend, huud.id()).block().code()).isEqualTo(huud.code());

        // A code finds the Huud; it doesn't open the door.
        var asked = huuds.joinByCode(stranger, huud.code()).block();
        assertThat(asked.youAreIn()).isFalse();
        assertThat(asked.code()).isNull();
        assertThat(asked.joinRequest()).isEqualTo("pending");
        var hostView = huuds.view(huud.id(), host).block();
        assertThat(hostView.requests()).extracting("kind").containsExactly("join");
        assertThat(huuds.view(huud.id(), friend).block().requests()).isEmpty();

        requests.answer(host, huud.id(), stranger, "join", true).block();
        var in = huuds.view(huud.id(), stranger).block();
        assertThat(in.youAreIn()).isTrue();
        assertThat(in.members()).hasSize(3);
    }

    @Test void aPrivateHuudIsInviteOrApprovalOnly() {
        UUID host = person("Host"), friend = person("Friend"), other = person("Other");
        befriend(host, friend);
        befriend(host, other);
        var huud = huuds.create(host, null, "private").block();
        assertThat(huuds.live(friend).collectList().block()).extracting("id").doesNotContain(huud.id());
        assertThat(huuds.joinByCode(friend, huud.code()).block().joinRequest()).isEqualTo("pending");

        requests.invite(host, huud.id(), other).block();
        assertThat(huuds.join(other, huud.id()).block().youAreIn()).isTrue();

        requests.answer(host, huud.id(), friend, "join", false).block();
        assertThat(huuds.view(huud.id(), friend).block().joinRequest()).isEqualTo("declined");
        // Not straight back at the host's door.
        assertThatThrownBy(() -> huuds.joinByCode(friend, huud.code()).block()).isInstanceOf(ResponseStatusException.class);
    }

    @Test void publicHuudsLetAnyoneIn() {
        var open = huuds.create(person("Public host"), null, "public").block();
        UUID stranger = person("Stranger");
        assertThat(huuds.live(stranger).collectList().block()).extracting("id").contains(open.id());
        assertThat(huuds.joinByCode(stranger, open.code()).block().youAreIn()).isTrue();
    }

    @Test void aLeavingHostHandsTheHuudToTheNextJoinerSkippingGuests() {
        UUID host = person("Host"), guestKid = guest("Guest"), second = person("Second"), third = person("Third");
        var huud = huuds.create(host, null, "public").block();
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
        assertThat(huuds.create(host, null, "public").block().id()).isNotEqualTo(huud.id());
    }

    @Test void aHostWhoseAppWentQuietIsReplacedByTheNextJoiner() {
        UUID host = person("Host"), second = person("Second"), third = person("Third");
        var huud = huuds.create(host, null, "public").block();
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
        var huud = huuds.create(host, null, "public").block();
        huuds.joinByCode(early, huud.code()).block();
        huuds.joinByCode(late, huud.code()).block();
        huuds.leave(early, huud.id()).block();
        huuds.joinByCode(early, huud.code()).block();

        huuds.leave(host, huud.id()).block();
        assertThat(huuds.view(huud.id(), early).block().host().userId()).isEqualTo(late);
    }

    @Test void theLastPersonLeavingEndsTheHuudAndItStaysInEveryonesHistory() {
        UUID host = person("Host"), friend = person("Friend");
        var huud = huuds.create(host, "Saturday", "public").block();
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
        var huud = huuds.create(host, null, "public").block();
        huuds.joinByCode(friend, huud.code()).block();
        quiet(huud.id(), host, "11 minutes");
        quiet(huud.id(), friend, "11 minutes");
        huuds.expire().block();
        assertThat(huuds.history(host).collectList().block().get(0).status()).isEqualTo("ended");
        assertThat(huuds.current(host).block()).isNull();
    }

    @Test void aHuudNobodyCameToAndNothingWasPlayedInStaysOutOfHistory() {
        UUID host = person("Host");
        var lonely = huuds.create(host, null, "public").block();
        assertThat(huuds.history(host).collectList().block()).extracting("id").containsExactly(lonely.id());
        huuds.end(host, lonely.id()).block();
        assertThat(huuds.history(host).collectList().block()).isEmpty();

        var played = huuds.create(host, null, "public").block();
        var room = huuds.addGame(host, played.id(), "draughts").block();
        db.sql("INSERT INTO game_sessions(room_id,game_type,config,catalog_version,rng_seed) "
                + "VALUES(:room,'draughts','{}',1,1)").bind("room", room.id()).fetch().rowsUpdated().block();
        db.sql("UPDATE rooms SET status='ended' WHERE id=:id").bind("id", room.id()).fetch().rowsUpdated().block();
        huuds.end(host, played.id()).block();
        assertThat(huuds.history(host).collectList().block()).extracting("id").containsExactly(played.id());
    }

    @Test void endingClosesTheHuudForEveryoneAndOnlyTheHostCanEnd() {
        UUID host = person("Host"), friend = person("Friend");
        var huud = huuds.create(host, null, "public").block();
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
        var huud = huuds.create(host, null, "public").block();
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

    @Test void beingInTheHuudIsNotASeatTheHostPicksWhoPlays() {
        UUID host = person("Host"), ada = person("Ada"), chidi = person("Chidi");
        var huud = huuds.create(host, null, "public", "draughts", null, false).block();
        huuds.joinByCode(ada, huud.code()).block();
        huuds.joinByCode(chidi, huud.code()).block();

        var adaView = huuds.view(huud.id(), ada).block();
        assertThat(adaView.currentGame().gameType()).isEqualTo("draughts");
        assertThat(adaView.currentGame().seats()).isEqualTo(2);
        assertThat(adaView.currentGame().youArePlaying()).isFalse();
        assertThat(huuds.view(huud.id(), host).block().currentGame().youArePlaying()).isTrue();

        assertThat(requests.askToPlay(ada, huud.id()).block().playRequest()).isEqualTo("pending");
        requests.askToPlay(chidi, huud.id()).block();
        assertThat(huuds.view(huud.id(), host).block().requests()).extracting("kind").containsExactly("play", "play");

        var after = requests.answer(host, huud.id(), ada, "play", true).block();
        assertThat(after.currentGame().players()).isEqualTo(2);
        assertThat(huuds.view(huud.id(), ada).block().currentGame().youArePlaying()).isTrue();
        // Draughts is two players: no seat left for Chidi.
        assertThatThrownBy(() -> requests.answer(host, huud.id(), chidi, "play", true).block())
                .isInstanceOf(ResponseStatusException.class);

        // A new game starts a fresh queue.
        db.sql("UPDATE rooms SET status='ended' WHERE id=:id").bind("id", after.currentGame().roomId()).fetch().rowsUpdated().block();
        huuds.addGame(host, huud.id(), "whot").block();
        assertThat(huuds.view(huud.id(), chidi).block().playRequest()).isNull();
    }

    @Test void everyoneListensAndTheHostHandsOutTheMic() {
        UUID host = person("Host"), kid = person("Kid");
        var huud = huuds.create(host, null, "public").block();
        huuds.joinByCode(kid, huud.code()).block();
        assertThat(access.canTalk(kid, huud.voiceRoom()).block()).isTrue();
        assertThat(access.canSpeak(kid, huud.voiceRoom()).block()).isFalse();
        assertThat(access.canSpeak(host, huud.voiceRoom()).block()).isTrue();

        assertThat(requests.askForMic(kid, huud.id()).block().micRequest()).isEqualTo("pending");
        requests.answer(host, huud.id(), kid, "mic", true).block();
        assertThat(access.canSpeak(kid, huud.voiceRoom()).block()).isTrue();
        assertThat(huuds.view(huud.id(), kid).block().youCanSpeak()).isTrue();

        requests.setMic(host, huud.id(), kid, false).block();
        assertThat(access.canSpeak(kid, huud.voiceRoom()).block()).isFalse();
        verify(livekit, atLeastOnce()).setCanPublish(huud.voiceRoom(), kid.toString(), false);
    }

    @Test void huudChatIsForPeopleInsideAndSlowsDownFloods() {
        UUID host = person("Host"), friend = person("Friend"), outsider = person("Outsider");
        var huud = huuds.create(host, null, "public").block();
        huuds.joinByCode(friend, huud.code()).block();

        chat.send(friend, huud.id(), "  Who wants Whot next?  ").block();
        var messages = chat.messages(host, huud.id(), null).collectList().block();
        assertThat(messages).extracting("body").containsExactly("Who wants Whot next?");
        assertThat(messages.get(0).from().userId()).isEqualTo(friend);
        assertThatThrownBy(() -> chat.send(outsider, huud.id(), "hi").block()).isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> chat.messages(outsider, huud.id(), null).collectList().block())
                .isInstanceOf(ResponseStatusException.class);

        for (int i = 0; i < 4; i++) chat.send(friend, huud.id(), "msg " + i).block();
        assertThatThrownBy(() -> chat.send(friend, huud.id(), "one too many").block())
                .isInstanceOf(ResponseStatusException.class);
    }

    @Test void blockingKeepsPeopleApartAndHidesTheirChat() {
        UUID host = person("Host"), bully = person("Bully"), friend = person("Friend");
        befriend(host, bully);
        var huud = huuds.create(host, null, "public").block();
        huuds.joinByCode(bully, huud.code()).block();
        huuds.joinByCode(friend, huud.code()).block();
        var said = chat.send(bully, huud.id(), "you're bad at this").block();

        safety.report(friend, bully, "mean", "kept being rude", huud.id(), said.id(), true).block();
        assertThat(chat.messages(friend, huud.id(), null).collectList().block()).isEmpty();
        assertThat(chat.messages(host, huud.id(), null).collectList().block()).hasSize(1);
        assertThat(db.sql("SELECT message_body FROM player_reports WHERE reporter_id=:me").bind("me", friend)
                .map((r, m) -> r.get("message_body", String.class)).one().block()).isEqualTo("you're bad at this");

        // The host blocks them: out of the Huud, no friendship, can't come back or see it.
        safety.block(host, bully).block();
        assertThat(huuds.view(huud.id(), host).block().members()).extracting("userId").doesNotContain(bully);
        assertThat(db.sql("SELECT count(*) AS n FROM friends WHERE (low_user_id=:a OR high_user_id=:a)").bind("a", bully)
                .map((r, m) -> ((Number) r.get("n")).intValue()).one().block()).isZero();
        assertThat(huuds.live(bully).collectList().block()).extracting("id").doesNotContain(huud.id());

        var other = huuds.create(person("Other host"), null, "public").block();
        UUID otherHost = other.host().userId();
        safety.block(otherHost, friend).block();
        assertThatThrownBy(() -> huuds.joinByCode(friend, other.code()).block()).isInstanceOf(ResponseStatusException.class);
        safety.unblock(otherHost, friend).block();
        assertThat(huuds.joinByCode(friend, other.code()).block().youAreIn()).isTrue();
    }

    @Test void aSharedHuudShowsOnTheFeedWithItsLineAndSeats() {
        UUID host = person("Eric"), friend = person("Friend"), stranger = person("Stranger");
        befriend(host, friend);
        var huud = huuds.create(host, null, "friends", "whot", "Who wants to play Whot?", true).block();
        assertThat(huud.shared()).isTrue();

        var item = feed.feed(friend, HuudDtos.Tab.FRIENDS, HuudDtos.Filter.ALL).collectList().block().stream()
                .filter(i -> "huud".equals(i.kind())).findFirst().orElseThrow();
        assertThat(item.message()).isEqualTo("Who wants to play Whot?");
        assertThat(item.gameType()).isEqualTo("whot");
        assertThat(item.huud().players()).isEqualTo(1);
        assertThat(item.huud().seats()).isEqualTo(4);
        assertThat(item.huud().access()).isEqualTo("join");
        assertThat(feed.feed(stranger, HuudDtos.Tab.FOR_YOU, HuudDtos.Filter.ALL).collectList().block())
                .extracting("kind").doesNotContain("huud");

        huuds.update(host, huud.id(), null, "public").block();
        assertThat(feed.feed(stranger, HuudDtos.Tab.FOR_YOU, HuudDtos.Filter.ALL).collectList().block().stream()
                .filter(i -> "huud".equals(i.kind())).findFirst().orElseThrow().huud().access()).isEqualTo("join");

        huuds.unshare(host, huud.id()).block();
        assertThat(feed.feed(friend, HuudDtos.Tab.FRIENDS, HuudDtos.Filter.ALL).collectList().block())
                .extracting("kind").doesNotContain("huud");
    }
}
