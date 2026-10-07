package app.truearena;

import app.truearena.api.competitive.RatingService;
import app.truearena.api.friends.FriendService;
import app.truearena.api.competitive.RatingService.FinishedGame;
import app.truearena.api.huud.HuudDtos.CreateChallengeRequest;
import app.truearena.api.huud.HuudDtos.CreatePostRequest;
import app.truearena.api.huud.HuudDtos.CreatedPost;
import app.truearena.api.huud.HuudDtos.FeedItem;
import app.truearena.api.huud.HuudDtos.Filter;
import app.truearena.api.huud.HuudDtos.Tab;
import app.truearena.api.huud.HuudService;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.web.server.ResponseStatusException;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The Huud feed's SQL against real Postgres: friend scoping, the challenge
 * lifecycle, and win cards built from match history. Same rig as
 * {@link CompetitiveRatingIT} — where Testcontainers can't start containers,
 * point it at an existing, EMPTY database:
 * <pre>
 *   ./mvnw -pl ta-app verify -Dit.test=HuudFeedIT \
 *     -Dit.r2dbc.url=r2dbc:postgresql://localhost:5433/scratch -Dit.jdbc.url=jdbc:postgresql://localhost:5433/scratch \
 *     -Dit.db.user=truearena -Dit.db.password=truearena -Dit.redis.port=6380 -Dit.redis.database=15
 * </pre>
 */
@SpringBootTest
@Tag("integration")
class HuudFeedIT {

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

    @Autowired HuudService huud;
    @Autowired RatingService ratings;
    @Autowired UserRepository users;
    @Autowired FriendService friends;
    @Autowired DatabaseClient db;

    // ---------------------------------------------------------------- fixtures

    private UUID human(String tag) {
        String unique = (tag + UUID.randomUUID()).replace("-", "").substring(0, 20);
        return users.save(UserRow.newUser(null, unique + "@huud.test", "Player " + tag, "h_" + unique))
                .map(UserRow::id).block();
    }

    private void befriend(UUID a, UUID b) {
        UUID low = FriendRow.lowerOf(a, b);
        UUID high = low.equals(a) ? b : a;
        db.sql("INSERT INTO friends (low_user_id, high_user_id, status, requested_by) VALUES (:l, :h, 'accepted', :l)")
                .bind("l", low).bind("h", high).fetch().rowsUpdated().block();
    }

    private List<FeedItem> feed(UUID viewer, Tab tab) {
        return huud.feed(viewer, tab, Filter.ALL).collectList().block();
    }

    private FeedItem card(UUID viewer, Tab tab, String id) {
        return feed(viewer, tab).stream().filter(i -> i.id().equals(id)).findFirst()
                .orElseThrow(() -> new AssertionError(id + " is not in the feed"));
    }

    private void setRoomStatus(UUID room, String status) {
        db.sql("UPDATE rooms SET status = :s WHERE id = :r").bind("s", status).bind("r", room)
                .fetch().rowsUpdated().block();
    }

    private static List<String> ids(List<FeedItem> items) {
        return items.stream().map(FeedItem::id).toList();
    }

    private void finishDraughts(UUID winner, UUID loser) {
        UUID room = db.sql("INSERT INTO rooms (code, host_id, game_type, ranked, status) "
                        + "VALUES (:code, :host, 'draughts', true, 'ended') RETURNING id")
                .bind("code", UUID.randomUUID().toString().substring(0, 8)).bind("host", winner)
                .map(row -> row.get("id", UUID.class)).one().block();
        UUID session = db.sql("INSERT INTO game_sessions (room_id, game_type, config, catalog_version, rng_seed, started_at) "
                        + "VALUES (:room, 'draughts', '{}'::jsonb, 1, 1, now() - interval '5 minutes') RETURNING id")
                .bind("room", room).map(row -> row.get("id", UUID.class)).one().block();
        ratings.recordMatch(new FinishedGame(session, room, "draughts", winner.toString(),
                Map.of(winner.toString(), "won", loser.toString(), "lost"),
                Set.of(winner.toString(), loser.toString()))).block();
    }

    // ---------------------------------------------------------------- open game requests

    @Test
    void aGameRequestReachesFriendsInYourHuudAndEveryoneInForYou() {
        UUID eric = human("eric");
        UUID amaka = human("amaka");
        UUID stranger = human("stranger");
        befriend(eric, amaka);

        CreatedPost post = huud.post(eric, new CreatePostRequest("draughts", "Winner stays on.", true, null)).block();
        String id = "post:" + post.postId();

        assertThat(post.room().status()).isEqualTo("lobby");
        assertThat(ids(feed(amaka, Tab.FRIENDS))).contains(id);
        assertThat(ids(feed(stranger, Tab.FRIENDS))).doesNotContain(id);
        assertThat(ids(feed(stranger, Tab.FOR_YOU))).contains(id);

        FeedItem card = feed(eric, Tab.FRIENDS).stream().filter(i -> i.id().equals(id)).findFirst().orElseThrow();
        assertThat(card.message()).isEqualTo("Winner stays on.");
        assertThat(card.game().mine()).isTrue();
        assertThat(card.game().joined()).isTrue();
        assertThat(card.game().ranked()).isTrue();
        assertThat(card.game().seats()).isEqualTo(2);
        assertThat(card.game().seatsTaken()).isEqualTo(1);
        assertThat(card.game().roomCode()).isEqualTo(post.room().code());
    }

    @Test
    void aFullRequestStaysOnTheFeedMarkedFilled() {
        UUID eric = human("full");
        UUID tunde = human("tunde");
        UUID watcher = human("watcher");
        CreatedPost post = huud.post(eric, new CreatePostRequest("chess", null, false, null)).block();
        String id = "post:" + post.postId();

        assertThat(card(watcher, Tab.FOR_YOU, id).game().filled()).isFalse();
        db.sql("INSERT INTO room_members (room_id, user_id, nickname) VALUES (:r, :u, 'tunde')")
                .bind("r", post.room().id()).bind("u", tunde).fetch().rowsUpdated().block();

        FeedItem filled = card(watcher, Tab.FOR_YOU, id);
        assertThat(filled.game().filled()).isTrue();
        assertThat(filled.game().seatsTaken()).isEqualTo(2);
        assertThat(filled.game().players()).extracting(p -> p.userId()).containsExactly(eric, tunde);
        assertThat(card(tunde, Tab.FOR_YOU, id).game().joined()).isTrue();

        // Once it's started it still reads as filled…
        setRoomStatus(post.room().id(), "in_game");
        assertThat(card(watcher, Tab.FOR_YOU, id).game().filled()).isTrue();
        // …and once it's over it's gone.
        setRoomStatus(post.room().id(), "ended");
        assertThat(ids(feed(watcher, Tab.FOR_YOU))).doesNotContain(id);
    }

    @Test
    void aStartedGameReadsAsFilledEvenWithSeatsLeft() {
        UUID host = human("early");
        CreatedPost post = huud.post(host, new CreatePostRequest("whot", null, false, 6)).block();
        setRoomStatus(post.room().id(), "in_game");

        FeedItem item = card(human("late"), Tab.FOR_YOU, "post:" + post.postId());
        assertThat(item.game().seatsTaken()).isEqualTo(1);
        assertThat(item.game().filled()).isTrue();
    }

    @Test
    void expiredPostsLeaveTheFeed() {
        UUID host = human("expired");
        CreatedPost post = huud.post(host, new CreatePostRequest("whot", null, false, null)).block();
        db.sql("UPDATE huud_posts SET created_at = now() - interval '1 hour', expires_at = now() - interval '1 minute' WHERE id = :id")
                .bind("id", post.postId()).fetch().rowsUpdated().block();

        assertThat(ids(feed(human("viewer"), Tab.FOR_YOU))).doesNotContain("post:" + post.postId());
    }

    @Test
    void aNewRequestReplacesTheAuthorsLastOne() {
        UUID eric = human("twice");
        CreatedPost first = huud.post(eric, new CreatePostRequest("whot", null, false, null)).block();
        CreatedPost second = huud.post(eric, new CreatePostRequest("ludo", null, false, 3)).block();

        List<String> mine = ids(feed(eric, Tab.FRIENDS));
        assertThat(mine).contains("post:" + second.postId()).doesNotContain("post:" + first.postId());
    }

    // ---------------------------------------------------------------- challenges

    @Test
    void aChallengeIsPinnedForItsTargetAndAcceptingJoinsTheRoom() {
        UUID tobi = human("tobi");
        UUID eric = human("target");
        UUID friendOfBoth = human("bystander");
        befriend(tobi, eric);
        befriend(tobi, friendOfBoth);
        befriend(eric, friendOfBoth);
        finishDraughts(eric, tobi);

        CreatedPost challenge = huud.challenge(tobi, new CreateChallengeRequest(eric, "draughts", "Rematch?", false))
                .block();
        String id = "post:" + challenge.postId();

        // Newer cards exist, but the challenge waiting on Eric is first.
        huud.post(friendOfBoth, new CreatePostRequest("whot", null, false, null)).block();
        List<FeedItem> erics = feed(eric, Tab.FRIENDS);
        assertThat(erics.get(0).id()).isEqualTo(id);
        assertThat(erics.get(0).game().lastOutcome()).isEqualTo("won");
        assertThat(erics.get(0).game().target().userId()).isEqualTo(eric);

        assertThat(ids(feed(tobi, Tab.FRIENDS))).contains(id);
        assertThat(ids(feed(friendOfBoth, Tab.FRIENDS))).doesNotContain(id);
        assertThat(ids(feed(eric, Tab.FOR_YOU))).doesNotContain(id);

        assertThatThrownBy(() -> huud.accept(friendOfBoth, challenge.postId()).block())
                .isInstanceOf(ResponseStatusException.class);

        RoomView room = huud.accept(eric, challenge.postId()).block();
        assertThat(room.id()).isEqualTo(challenge.room().id());
        assertThat(room.members()).extracting(m -> m.userId()).contains(eric, tobi);
        assertThat(ids(feed(eric, Tab.FRIENDS))).doesNotContain(id);

        assertThatThrownBy(() -> huud.accept(eric, challenge.postId()).block())
                .isInstanceOf(ResponseStatusException.class);
    }

    @Test
    void decliningRemovesTheChallengeFromBothFeeds() {
        UUID tobi = human("decliner");
        UUID eric = human("declined");
        CreatedPost challenge = huud.challenge(tobi, new CreateChallengeRequest(eric, "whot", null, false)).block();
        String id = "post:" + challenge.postId();

        huud.decline(eric, challenge.postId()).block();

        assertThat(ids(feed(eric, Tab.FRIENDS))).doesNotContain(id);
        assertThat(ids(feed(tobi, Tab.FRIENDS))).doesNotContain(id);
    }

    // ---------------------------------------------------------------- wins

    @Test
    void winsComeFromMatchHistoryWithTheStreakAndRating() {
        UUID chidi = human("chidi");
        UUID loser = human("loser");
        UUID friend = human("chidifriend");
        befriend(chidi, friend);
        for (int i = 0; i < 3; i++) {
            finishDraughts(chidi, loser);
        }

        FeedItem card = feed(friend, Tab.FRIENDS).stream()
                .filter(i -> "win".equals(i.kind()) && i.actor().userId().equals(chidi))
                .findFirst().orElseThrow();
        assertThat(card.gameType()).isEqualTo("draughts");
        assertThat(card.win().streak()).isEqualTo(3);
        assertThat(card.win().recent()).containsExactly("won", "won", "won");
        assertThat(card.win().ranked()).isTrue();
        assertThat(card.win().rating()).isGreaterThan(1500.0);
        assertThat(card.win().weekDelta()).isPositive();
        assertThat(card.win().beaten()).containsExactly("Player loser");

        // One card per player per game, not one per match.
        assertThat(feed(friend, Tab.FRIENDS).stream()
                .filter(i -> "win".equals(i.kind()) && i.actor().userId().equals(chidi))).hasSize(1);

        // Ranked, public profile → it's in the public lobby too.
        assertThat(feed(human("anyone"), Tab.FOR_YOU)).extracting(FeedItem::id).contains(card.id());
    }

    @Test
    void aPrivateProfilesWinsStayWithFriends() {
        UUID quiet = human("quiet");
        UUID loser = human("quietloser");
        UUID friend = human("quietfriend");
        befriend(quiet, friend);
        db.sql("INSERT INTO competitive_profiles (user_id, profile_public) VALUES (:u, false)")
                .bind("u", quiet).fetch().rowsUpdated().block();
        finishDraughts(quiet, loser);

        assertThat(feed(friend, Tab.FRIENDS)).anyMatch(i -> "win".equals(i.kind()) && i.actor().userId().equals(quiet));
        assertThat(feed(human("outsider"), Tab.FOR_YOU))
                .noneMatch(i -> "win".equals(i.kind()) && i.actor().userId().equals(quiet));
    }

    // ---------------------------------------------------------------- tournaments

    @Test
    void publicTournamentsOpenForRegistrationShowWithTheirSignUps() {
        UUID host = human("host");
        UUID entrant = human("entrant");
        UUID friend = human("hostfriend");
        befriend(host, friend);
        UUID championship = db.sql("INSERT INTO championships (code, name, game_type, size, visibility, scheduled_at, creator_id) "
                        + "VALUES (:code, 'Nigeria Draughts Championship', 'draughts', 32, 'public', now() + interval '3 days', :host) "
                        + "RETURNING id")
                .bind("code", UUID.randomUUID().toString().substring(0, 8)).bind("host", host)
                .map(row -> row.get("id", UUID.class)).one().block();
        db.sql("INSERT INTO championship_participants (championship_id, user_id, slot) VALUES (:c, :u, 0)")
                .bind("c", championship).bind("u", entrant).fetch().rowsUpdated().block();

        FeedItem card = huud.feed(human("browser"), Tab.FOR_YOU, Filter.TOURNAMENTS).collectList().block().stream()
                .filter(i -> i.id().equals("tournament:" + championship)).findFirst().orElseThrow();
        assertThat(card.tournament().name()).isEqualTo("Nigeria Draughts Championship");
        assertThat(card.tournament().joined()).isEqualTo(1);
        assertThat(card.tournament().size()).isEqualTo(32);
        assertThat(card.tournament().viewerJoined()).isFalse();

        assertThat(ids(feed(friend, Tab.FRIENDS))).contains("tournament:" + championship);
        assertThat(huud.feed(friend, Tab.FRIENDS, Filter.OPEN).collectList().block()).isEmpty();
    }

    // ---------------------------------------------------------------- search

    @Test
    void theSearchBarFindsAPlayerByTheirPlayHuudNumber() {
        UUID me = human("searcher");
        UUID ngozi = human("ngozi");
        long number = users.playhuudNumberOf(ngozi).block();

        assertThat(friends.search(me, "#" + number).collectList().block())
                .extracting(r -> r.userId()).first().isEqualTo(ngozi);
        assertThat(friends.search(me, String.valueOf(number)).collectList().block())
                .extracting(r -> r.userId()).first().isEqualTo(ngozi);
    }
    // ---------------------------------------------------------------- guards

    @Test
    void onlyTheAuthorCanTakeDownAPost() {
        UUID host = human("owner");
        CreatedPost post = huud.post(host, new CreatePostRequest("whot", null, false, null)).block();

        assertThatThrownBy(() -> huud.close(human("other"), post.postId()).block())
                .isInstanceOf(ResponseStatusException.class);
        huud.close(host, post.postId()).block();
        assertThat(ids(feed(host, Tab.FRIENDS))).doesNotContain("post:" + post.postId());
    }

    @Test
    void challengesRefuseCyberAgentsAndExpire() {
        UUID me = human("challenger");
        UUID agent = users.save(UserRow.newBot("Agent", "a_" + UUID.randomUUID().toString().substring(0, 12), null,
                "whot", "easy")).map(UserRow::id).block();
        assertThatThrownBy(() -> huud.challenge(me, new CreateChallengeRequest(agent, "whot", null, false)).block())
                .isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> huud.challenge(me, new CreateChallengeRequest(me, "whot", null, false)).block())
                .isInstanceOf(ResponseStatusException.class);

        UUID target = human("slow");
        CreatedPost challenge = huud.challenge(me, new CreateChallengeRequest(target, "whot", null, false)).block();
        db.sql("UPDATE huud_posts SET created_at = now() - interval '1 hour', expires_at = now() - interval '1 minute' WHERE id = :id")
                .bind("id", challenge.postId()).fetch().rowsUpdated().block();
        assertThatThrownBy(() -> huud.accept(target, challenge.postId()).block())
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("expired");
    }

    // ---------------------------------------------------------------- speed

    /**
     * A busy lobby: 120 open requests and 400 finished matches from 60
     * players in the last two days. The feed must stay one page and fast —
     * this is the regression guard for per-card queries creeping back in.
     */
    @Test
    void aBusyLobbyStillServesOnePageQuickly() {
        UUID viewer = human("busyviewer");
        List<UUID> crowd = new java.util.ArrayList<>();
        for (int i = 0; i < 60; i++) {
            UUID p = human("crowd" + i);
            crowd.add(p);
            if (i % 3 == 0) {
                befriend(viewer, p);
            }
        }
        for (int i = 0; i < 120; i++) {
            UUID host = crowd.get(i % crowd.size());
            UUID room = db.sql("INSERT INTO rooms (code, host_id, game_type) VALUES (:c, :h, 'whot') RETURNING id")
                    .bind("c", UUID.randomUUID().toString().substring(0, 8)).bind("h", host)
                    .map(r -> r.get("id", UUID.class)).one().block();
            db.sql("INSERT INTO room_members (room_id, user_id, nickname) VALUES (:r, :u, 'x')")
                    .bind("r", room).bind("u", host).fetch().rowsUpdated().block();
            db.sql("INSERT INTO huud_posts (author_id, kind, room_id, game_type, seats, expires_at) "
                            + "VALUES (:a, 'game_request', :r, 'whot', 4, now() + interval '10 minutes')")
                    .bind("a", host).bind("r", room).fetch().rowsUpdated().block();
        }
        for (int i = 0; i < 400; i++) {
            UUID winner = crowd.get(i % crowd.size());
            UUID loser = crowd.get((i * 7 + 1) % crowd.size());
            if (winner.equals(loser)) {
                continue;
            }
            UUID match = db.sql("INSERT INTO match_records (game_type, ranked, player_count, completed_at) "
                            + "VALUES ('draughts', true, 2, now() - (:m || ' minutes')::interval) RETURNING id")
                    .bind("m", String.valueOf(i * 5)).map(r -> r.get("id", UUID.class)).one().block();
            db.sql("INSERT INTO match_participants (match_id, user_id, outcome) VALUES (:m, :w, 'won'), (:m, :l, 'lost')")
                    .bind("m", match).bind("w", winner).bind("l", loser).fetch().rowsUpdated().block();
        }

        for (Tab tab : Tab.values()) {
            feed(viewer, tab); // warm up
            long best = Long.MAX_VALUE;
            List<FeedItem> page = List.of();
            for (int run = 0; run < 3; run++) {
                long start = System.nanoTime();
                page = feed(viewer, tab);
                best = Math.min(best, (System.nanoTime() - start) / 1_000_000);
            }
            assertThat(page).hasSizeLessThanOrEqualTo(40).isNotEmpty();
            assertThat(page).extracting(FeedItem::id).doesNotHaveDuplicates();
            assertThat(best).as("%s feed took %d ms", tab, best).isLessThan(400);
        }
    }
}
