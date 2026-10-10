package app.truearena;
import app.truearena.api.huudspace.HuudSpaceAccess;
import app.truearena.api.huudspace.HuudSpaceService;
import app.truearena.api.huudspace.HuudSpaceRequestService;
import app.truearena.api.huudspace.HuudSpaceChatService;
import app.truearena.api.huud.HuudDtos;
import app.truearena.api.huud.HuudService;
import app.truearena.api.huud.FeedPostService;
import app.truearena.api.admin.AdminReportsController;
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
    @Autowired FeedPostService posts;
    @Autowired AdminReportsController adminReports;
    @Autowired UserRepository users;
    @Autowired FriendRepository friendRows;
    @Autowired DatabaseClient db;
    @Autowired UserNotificationRepository notes;
    @Autowired app.truearena.api.coins.GiftController gifts;
    @Autowired app.truearena.api.competitive.AllTimeRankingController rankings;
    @org.springframework.boot.test.mock.mockito.SpyBean InboxRegistry inbox;
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
        assertThat(first.youOwn()).isTrue();
        assertThat(first.live()).isTrue();
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

    @Test void theOwnerCantLeaveTheirOwnHuudButMembersCanAndThenHearNothingMore() {
        UUID owner = person("Owner"), friend = person("Friend");
        var huud = huuds.create(owner, null, "public").block();
        huuds.joinByCode(friend, huud.code()).block();
        assertThatThrownBy(() -> huuds.leave(owner, huud.id()).block()).isInstanceOf(ResponseStatusException.class);

        huuds.leave(friend, huud.id()).block();
        assertThat(huuds.mine(friend).collectList().block()).isEmpty();
        assertThat(huuds.view(huud.id(), owner).block().members()).extracting("userId").containsExactly(owner);

        // Gone means no Live notification next time.
        huuds.endLive(owner, huud.id()).block();
        clearInvocations(inbox);
        huuds.goLive(owner, huud.id(), "all").block();
        verify(inbox, never()).notify(eq(friend), any());
    }

    @Test void whileLiveAnAwayHostIsCoveredByTheNextJoinerAndTheOwnerTakesBackOver() {
        UUID owner = person("Owner"), guestKid = guest("Guest"), second = person("Second"), third = person("Third");
        var huud = huuds.create(owner, null, "public").block();
        huuds.joinByCode(guestKid, huud.code()).block();
        huuds.joinByCode(second, huud.code()).block();
        huuds.joinByCode(third, huud.code()).block();

        quiet(huud.id(), owner, "4 minutes");
        huuds.expire().block();
        assertThat(huuds.view(huud.id(), third).block().host().userId()).isEqualTo(owner);

        quiet(huud.id(), owner, "6 minutes");
        huuds.expire().block();
        var covered = huuds.view(huud.id(), third).block();
        // Guests can't run a Huud: the second person in does.
        assertThat(covered.host().userId()).isEqualTo(second);
        assertThat(covered.members()).extracting("userId").contains(owner);
        assertThat(huuds.current(owner).block().id()).isEqualTo(huud.id());

        // The owner opening it again is walking back in — and taking over.
        var back = huuds.view(huud.id(), owner).block();
        assertThat(back.youAreHost()).isTrue();
        assertThat(back.host().userId()).isEqualTo(owner);
    }

    @Test void endingLiveKeepsTheHuudItsPeopleCodeAndChatAndResetsTheHangout() {
        UUID owner = person("Owner"), friend = person("Friend"), viewer = person("Viewer");
        var huud = huuds.create(owner, "Saturday", "public", "draughts", "Who's in?", true).block();
        huuds.joinByCode(friend, huud.code()).block();
        requests.askForMic(friend, huud.id()).block();
        huuds.watch(viewer, huud.id()).block();
        chat.send(friend, huud.id(), "gg").block();
        assertThatThrownBy(() -> huuds.endLive(friend, huud.id()).block()).isInstanceOf(ResponseStatusException.class);

        var offline = huuds.endLive(owner, huud.id()).block();
        assertThat(offline.live()).isFalse();
        assertThat(offline.status()).isEqualTo("active");
        assertThat(offline.code()).isEqualTo(huud.code());
        assertThat(offline.name()).isEqualTo("Saturday");
        assertThat(offline.currentGame()).isNull();
        assertThat(offline.shared()).isFalse();
        assertThat(offline.requests()).isEmpty();
        assertThat(offline.memberCount()).isEqualTo(2);
        assertThat(offline.liveCount()).isZero();
        assertThat(access.canTalk(friend, huud.voiceRoom()).block()).isFalse();
        assertThat(chat.messages(friend, huud.id(), null).collectList().block()).extracting("body").containsExactly("gg");
        assertThat(huuds.live(viewer).collectList().block()).extracting("id").doesNotContain(huud.id());
        assertThatThrownBy(() -> huuds.watch(viewer, huud.id()).block()).isInstanceOf(ResponseStatusException.class);

        // Back Live with the same code and the same people.
        var again = huuds.goLive(owner, huud.id(), "none").block();
        assertThat(again.live()).isTrue();
        assertThat(again.code()).isEqualTo(huud.code());
        assertThat(again.memberCount()).isEqualTo(2);
        assertThat(again.liveCount()).isEqualTo(1);
        assertThat(huuds.view(huud.id(), friend).block().liveCount()).isEqualTo(2);
    }

    @Test void goingLiveTellsMembersWhoHaventMutedItTheWayTheHostChose() {
        UUID owner = person("Owner"), ada = person("Ada"), muted = person("Muted");
        var huud = huuds.create(owner, null, "public").block();
        huuds.joinByCode(ada, huud.code()).block();
        huuds.joinByCode(muted, huud.code()).block();
        assertThat(huuds.mute(muted, huud.id(), true).block().muted()).isTrue();
        huuds.endLive(owner, huud.id()).block();

        clearInvocations(inbox);
        huuds.goLive(owner, huud.id(), "all").block();
        verify(inbox).notify(eq(ada), argThat(event -> event.toString().contains("event=live")));
        verify(inbox, never()).notify(eq(muted), argThat(event -> event.toString().contains("event=live")));

        huuds.endLive(owner, huud.id()).block();
        clearInvocations(inbox);
        huuds.goLive(owner, huud.id(), "none").block();
        verify(inbox, never()).notify(eq(ada), argThat(event -> event.toString().contains("event=live")));

        huuds.endLive(owner, huud.id()).block();
        clearInvocations(inbox);
        // Nobody has the app open in a test: "online only" reaches nobody.
        huuds.goLive(owner, huud.id(), "online").block();
        verify(inbox, never()).notify(eq(ada), argThat(event -> event.toString().contains("event=live")));

        assertThatThrownBy(() -> huuds.goLive(ada, huud.id(), "all").block()).isInstanceOf(ResponseStatusException.class);
    }

    @Test void youCanJoinWhileItsOfflineAndBeThereNextTimeItsLive() {
        UUID owner = person("Owner"), early = person("Early");
        var huud = huuds.create(owner, null, "public").block();
        huuds.endLive(owner, huud.id()).block();

        var joined = huuds.joinByCode(early, huud.code()).block();
        assertThat(joined.youAreIn()).isTrue();
        assertThat(joined.live()).isFalse();
        assertThat(joined.liveCount()).isZero();
        assertThat(huuds.mine(early).collectList().block()).extracting("id").containsExactly(huud.id());
        assertThatThrownBy(() -> requests.askToPlay(early, huud.id()).block()).isInstanceOf(ResponseStatusException.class);

        huuds.goLive(owner, huud.id(), "all").block();
        var mine = huuds.mine(early).collectList().block().get(0);
        assertThat(mine.live()).isTrue();
        assertThat(mine.youOwn()).isFalse();
    }

    @Test void beingAwayOnlyTakesYouOutOfTheHangoutAndAnEmptyHangoutEndsLive() {
        UUID owner = person("Owner"), friend = person("Friend");
        var huud = huuds.create(owner, null, "public").block();
        huuds.joinByCode(friend, huud.code()).block();
        var waiting = huuds.addGame(owner, huud.id(), "chess").block();
        quiet(huud.id(), owner, "11 minutes");
        quiet(huud.id(), friend, "11 minutes");
        huuds.expire().block();

        var after = huuds.view(huud.id(), friend).block();
        // Just opening it again walks you in — so look via the owner's list instead.
        var mine = huuds.mine(owner).collectList().block().get(0);
        assertThat(mine.live()).isFalse();
        assertThat(mine.memberCount()).isEqualTo(2);
        assertThat(after.status()).isEqualTo("active");
        assertThat(db.sql("SELECT count(*) AS n FROM rooms WHERE id=:id AND status='lobby'").bind("id", waiting.id())
                .map((r, m) -> ((Number) r.get("n")).intValue()).one().block()).isZero();
    }

    @Test void theOwnerCanDeleteTheirHuudForEveryone() {
        UUID owner = person("Owner"), friend = person("Friend");
        var huud = huuds.create(owner, null, "public").block();
        huuds.joinByCode(friend, huud.code()).block();
        assertThatThrownBy(() -> huuds.delete(friend, huud.id()).block()).isInstanceOf(ResponseStatusException.class);
        huuds.delete(owner, huud.id()).block();
        assertThat(huuds.current(owner).block()).isNull();
        assertThat(huuds.mine(friend).collectList().block()).isEmpty();
        assertThatThrownBy(() -> huuds.joinByCode(person("Late"), huud.code()).block())
                .isInstanceOf(ResponseStatusException.class);
        // A brand-new Huud next time, with a new code.
        var fresh = huuds.create(owner, null, null).block();
        assertThat(fresh.id()).isNotEqualTo(huud.id());
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
        assertThat(huuds.mine(rude).collectList().block()).isEmpty();
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

    @Test void watchingIsLookingInWithoutJoining() {
        UUID host = person("Host"), player = person("Player"), viewer = person("Viewer");
        var huud = huuds.create(host, null, "public", "draughts", null, false).block();
        huuds.joinByCode(player, huud.code()).block();
        requests.askToPlay(player, huud.id()).block();
        requests.answer(host, huud.id(), player, "play", true).block();

        var watching = huuds.watch(viewer, huud.id()).block();
        assertThat(watching.youAreIn()).isFalse();
        assertThat(watching.code()).isNull();
        // Watchers see the game by its room, never its join code.
        assertThat(watching.currentGame().roomId()).isNotNull();
        assertThat(watching.currentGame().code()).isNull();
        assertThat(huuds.view(huud.id(), player).block().currentGame().code()).isNotNull();
        assertThat(huuds.view(huud.id(), host).block().watching()).isEqualTo(1);
        assertThat(huuds.live(host).collectList().block().stream().filter(l -> l.id().equals(huud.id()))
                .findFirst().orElseThrow().watching()).isEqualTo(1);
        assertThatThrownBy(() -> chat.send(viewer, huud.id(), "hi").block()).isInstanceOf(ResponseStatusException.class);

        // Joining turns a watcher into someone in the Huud.
        huuds.join(viewer, huud.id()).block();
        assertThat(huuds.view(huud.id(), host).block().watching()).isZero();

        var secret = huuds.create(person("Secret host"), null, "private").block();
        assertThatThrownBy(() -> huuds.watch(viewer, secret.id()).block()).isInstanceOf(ResponseStatusException.class);
    }

    @Test void rematchSeatsTheSamePlayersAgain() {
        UUID host = person("Host"), ada = person("Ada"), chidi = person("Chidi"), late = person("Late");
        var huud = huuds.create(host, null, "public", "whot", null, false).block();
        for (UUID p : new UUID[]{ada, chidi, late}) huuds.joinByCode(p, huud.code()).block();
        for (UUID p : new UUID[]{ada, chidi}) {
            requests.askToPlay(p, huud.id()).block();
            requests.answer(host, huud.id(), p, "play", true).block();
        }
        var first = huuds.view(huud.id(), host).block().currentGame();
        db.sql("UPDATE rooms SET status='ended' WHERE id=:id").bind("id", first.roomId()).fetch().rowsUpdated().block();
        huuds.leave(chidi, huud.id()).block();

        var again = huuds.addGame(host, huud.id(), "whot", true).block();
        assertThat(again.id()).isNotEqualTo(first.roomId());
        var game = huuds.view(huud.id(), host).block().currentGame();
        // Chidi left the Huud, so only Ada comes back with the host.
        assertThat(game.playerIds()).containsExactlyInAnyOrder(host, ada);
        assertThat(huuds.view(huud.id(), late).block().currentGame().youArePlaying()).isFalse();
    }

    @Test void textPostsGoToFriendsOnlyAndCanBeReportedAndTakenDown() {
        UUID me = person("Me"), friend = person("Friend"), stranger = person("Stranger");
        befriend(me, friend);
        var post = posts.post(me, "  Anyone up for Ludo later?  ").block();
        assertThat(post.message()).isEqualTo("Anyone up for Ludo later?");

        assertThat(feed.feed(friend, HuudDtos.Tab.FRIENDS, HuudDtos.Filter.ALL).collectList().block())
                .extracting("message").contains("Anyone up for Ludo later?");
        assertThat(feed.feed(stranger, HuudDtos.Tab.FRIENDS, HuudDtos.Filter.ALL).collectList().block())
                .extracting("kind").doesNotContain("post");
        assertThat(feed.feed(stranger, HuudDtos.Tab.FOR_YOU, HuudDtos.Filter.ALL).collectList().block())
                .extracting("kind").doesNotContain("post");
        assertThatThrownBy(() -> posts.post(me, "   ").block()).isInstanceOf(ResponseStatusException.class);
        for (int i = 0; i < 4; i++) posts.post(me, "post " + i).block();
        assertThatThrownBy(() -> posts.post(me, "one too many").block()).isInstanceOf(ResponseStatusException.class);

        UUID postId = UUID.fromString(post.id().substring("text:".length()));
        safety.report(friend, me, "mean", null, null, null, postId, false).block();
        var report = adminReports.list("open", 50).collectList().block().stream()
                .filter(r -> postId.equals(r.postId())).findFirst().orElseThrow();
        assertThat(report.postBody()).isEqualTo("Anyone up for Ludo later?");
        assertThat(report.reported().id()).isEqualTo(me);
        assertThat(report.reportsAgainst()).isGreaterThanOrEqualTo(1);

        adminReports.review(report.id(), new AdminReportsController.ReviewRequest("removed, talked to them", "Eric", true)).block();
        assertThat(adminReports.list("open", 50).collectList().block()).extracting("id").doesNotContain(report.id());
        var reviewed = adminReports.list("reviewed", 50).collectList().block().stream()
                .filter(r -> r.id().equals(report.id())).findFirst().orElseThrow();
        assertThat(reviewed.postRemoved()).isTrue();
        assertThat(reviewed.reviewNote()).isEqualTo("removed, talked to them");
        assertThat(feed.feed(friend, HuudDtos.Tab.FRIENDS, HuudDtos.Filter.ALL).collectList().block())
                .extracting("message").doesNotContain("Anyone up for Ludo later?");

        // Your own post: yours to delete; nobody else's.
        var mine = posts.post(friend, "gg").block();
        UUID mineId = UUID.fromString(mine.id().substring("text:".length()));
        assertThatThrownBy(() -> posts.delete(me, mineId).block()).isInstanceOf(ResponseStatusException.class);
        posts.delete(friend, mineId).block();
    }

    @Test void friendsReactToPostsOneReactionEachAndTheSameOneTakesItBack() {
        UUID me = person("Me"), ada = person("Ada"), tobi = person("Tobi"), stranger = person("Stranger");
        befriend(me, ada);
        befriend(me, tobi);
        var post = posts.post(me, "GG all").block();
        UUID id = UUID.fromString(post.id().substring("text:".length()));

        posts.react(ada, id, "❤️").block();
        var after = posts.react(tobi, id, "😂").block();
        assertThat(after.total()).isEqualTo(2);
        assertThat(after.counts()).containsEntry("❤️", 1).containsEntry("😂", 1);
        assertThat(after.mine()).isEqualTo("😂");

        // A different one replaces yours; the same one again takes it back.
        assertThat(posts.react(ada, id, "🔥").block().counts()).containsEntry("🔥", 1).doesNotContainKey("❤️");
        assertThat(posts.react(ada, id, "🔥").block().total()).isEqualTo(1);

        assertThatThrownBy(() -> posts.react(stranger, id, "👍").block()).isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> posts.react(ada, id, "💩").block()).isInstanceOf(ResponseStatusException.class);

        var item = feed.feed(me, HuudDtos.Tab.FRIENDS, HuudDtos.Filter.ALL).collectList().block().stream()
                .filter(i -> i.id().equals(post.id())).findFirst().orElseThrow();
        assertThat(item.reactions().total()).isEqualTo(1);
        assertThat(item.reactions().mine()).isNull();
    }

    @Test void theHostPicksPlayersFromTheHuudUpToTheSeatsAndCanChangeTheirMind() {
        UUID host = person("Host"), ada = person("Ada"), chidi = person("Chidi"), outsider = person("Outsider");
        var huud = huuds.create(host, null, "public", "draughts", null, false).block();
        huuds.joinByCode(ada, huud.code()).block();
        huuds.joinByCode(chidi, huud.code()).block();

        assertThatThrownBy(() -> requests.pick(host, huud.id(), java.util.List.of(outsider)).block())
                .isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> requests.pick(ada, huud.id(), java.util.List.of(chidi)).block())
                .isInstanceOf(ResponseStatusException.class);
        // Draughts seats two: the host and one more.
        assertThatThrownBy(() -> requests.pick(host, huud.id(), java.util.List.of(ada, chidi)).block())
                .isInstanceOf(ResponseStatusException.class);

        var picked = requests.pick(host, huud.id(), java.util.List.of(ada)).block();
        assertThat(picked.currentGame().playerIds()).containsExactlyInAnyOrder(host, ada);
        assertThat(picked.currentGame().table()).extracting("displayName").contains("Ada");
        assertThat(picked.currentGame().readyIds()).isEmpty();
        assertThat(huuds.view(huud.id(), ada).block().currentGame().youArePlaying()).isTrue();

        var swapped = requests.unpick(host, huud.id(), ada).block();
        assertThat(swapped.currentGame().playerIds()).containsExactly(host);
        requests.pick(host, huud.id(), java.util.List.of(chidi)).block();
        assertThat(huuds.view(huud.id(), chidi).block().currentGame().youArePlaying()).isTrue();
        assertThatThrownBy(() -> requests.unpick(host, huud.id(), host).block()).isInstanceOf(ResponseStatusException.class);
    }

    @Test void theHostPicksABackdropEveryoneSees() {
        UUID host = person("Host"), friend = person("Friend");
        var huud = huuds.create(host, null, "public").block();
        huuds.joinByCode(friend, huud.code()).block();
        assertThat(huud.background()).isNull();
        assertThat(huuds.update(host, huud.id(), null, null, "club").block().background()).isEqualTo("club");
        assertThat(huuds.view(huud.id(), friend).block().background()).isEqualTo("club");
        // Changing the name leaves the backdrop alone; "default" clears it.
        assertThat(huuds.update(host, huud.id(), "Party", null, null).block().background()).isEqualTo("club");
        assertThat(huuds.update(host, huud.id(), null, null, "default").block().background()).isNull();
        assertThatThrownBy(() -> huuds.update(friend, huud.id(), null, null, "lounge").block())
                .isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> huuds.update(host, huud.id(), null, null, "space").block())
                .isInstanceOf(ResponseStatusException.class);
    }

    @Test void aNotificationSwipedAwayIsGoneButOnlyYoursCanBe() {
        UUID ada = person("Ada Obi");
        UUID tobi = person("Tobi Ade");
        UUID note = db.sql("INSERT INTO user_notifications(user_id,type,title,body) VALUES(:u,'HUUD_SPACE','PlayHuud','Ada is live') RETURNING id")
                .bind("u", ada).map((r, m) -> r.get("id", UUID.class)).one().block();

        notes.deleteOwn(note, tobi).block();
        assertThat(notes.findTop50ByUserIdOrderByCreatedAtDesc(ada).collectList().block()).hasSize(1);

        notes.deleteOwn(note, ada).block();
        assertThat(notes.findTop50ByUserIdOrderByCreatedAtDesc(ada).collectList().block()).isEmpty();
    }

    long coins(UUID user, String column) {
        return db.sql("SELECT " + column + " FROM users WHERE id = :u").bind("u", user)
                .map((r, m) -> r.get(column, Long.class)).one().block();
    }

    @Test void giftingMovesThreeCoinsAndTellsThemButNeverRaisesTheirTier() {
        UUID ada = person("Ada Obi");
        UUID tobi = person("Tobi Ade");
        db.sql("UPDATE users SET coins = 10 WHERE id = :u").bind("u", ada).fetch().rowsUpdated().block();
        long tobiLifetime = coins(tobi, "lifetime_coins");

        var gift = gifts.give(ada, tobi).block();
        assertThat(gift.coins()).isEqualTo(3);
        assertThat(gift.balance()).isEqualTo(7);
        assertThat(coins(ada, "coins")).isEqualTo(7);
        assertThat(coins(tobi, "coins")).isEqualTo(3 + 0);
        assertThat(coins(tobi, "lifetime_coins")).isEqualTo(tobiLifetime);
        verify(inbox).notify(eq(tobi), argThat(e -> e.toString().contains("COIN_GIFT")));

        // Not enough left after two more: nothing moves on the third.
        gifts.give(ada, tobi).block();
        gifts.give(ada, tobi).block();
        assertThatThrownBy(() -> gifts.give(ada, tobi).block()).isInstanceOf(ResponseStatusException.class);
        assertThat(coins(ada, "coins")).isEqualTo(1);
        assertThat(coins(tobi, "coins")).isEqualTo(9);

        assertThatThrownBy(() -> gifts.give(ada, ada).block()).isInstanceOf(ResponseStatusException.class);
        safety.block(tobi, ada).block();
        db.sql("UPDATE users SET coins = 10 WHERE id = :u").bind("u", ada).fetch().rowsUpdated().block();
        assertThatThrownBy(() -> gifts.give(ada, tobi).block()).isInstanceOf(ResponseStatusException.class);
    }

    void played(UUID user, String game, int wins, int draws, int losses) {
        db.sql("INSERT INTO player_game_stats (user_id, game_type, games_played, wins, losses, draws) "
                        + "VALUES (:u, :g, :n, :w, :l, :d)")
                .bind("u", user).bind("g", game).bind("n", wins + draws + losses)
                .bind("w", wins).bind("l", losses).bind("d", draws).fetch().rowsUpdated().block();
    }

    @Test void allTimeRankingsOrderEveryoneByStrengthPerGameAndOverall() {
        String game = "zz" + UUID.randomUUID().toString().substring(0, 6); // a board of our own
        UUID ada = person("Ada Obi");
        UUID tobi = person("Tobi Ade");
        UUID zara = person("Zara Bello");
        UUID bot = guest("Guest");
        played(ada, game, 3, 0, 1);   // 63
        played(tobi, game, 1, 2, 5);  // 51
        played(zara, game, 4, 0, 0);  // 80
        played(bot, game, 50, 0, 0);  // guests aren't ranked

        var board = rankings.ranking(game, tobi).block();
        assertThat(board.top()).extracting("userId").containsExactly(zara, ada, tobi);
        assertThat(board.top()).extracting("strength").containsExactly(80L, 63L, 51L);
        assertThat(board.you().rank()).isEqualTo(3);

        var overall = rankings.ranking(null, ada).block();
        assertThat(overall.top()).hasSizeLessThanOrEqualTo(20);
        assertThat(overall.you().strength()).isGreaterThanOrEqualTo(63L);
    }

    @Test void anInviteLinkShowsTheHuudsNameOwnerAndHowManyAreInIt() {
        UUID ada = person("Ada Obi");
        var huud = huuds.create(ada, "Friday Whot", "friends").block();
        var preview = huuds.invitePreview(huud.code().toLowerCase()).block();
        assertThat(preview.name()).isEqualTo("Friday Whot");
        assertThat(preview.owner()).startsWith("h_");
        assertThat(preview.live()).isTrue();
        assertThat(preview.members()).isEqualTo(1);
        assertThatThrownBy(() -> huuds.invitePreview("NOPE00").block()).isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> huuds.invitePreview("x'; --").block()).isInstanceOf(ResponseStatusException.class);
    }
}
