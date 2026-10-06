package app.truearena;

import app.truearena.api.competitive.CompetitiveDtos.CompetitiveProfileView;
import app.truearena.api.competitive.CompetitiveDtos.LeaderboardView;
import app.truearena.api.competitive.CompetitiveDtos.UpdateLocationRequest;
import app.truearena.api.competitive.CompetitiveProfileService;
import app.truearena.api.competitive.LeaderboardScope;
import app.truearena.api.competitive.LeaderboardService;
import app.truearena.api.competitive.RatingService;
import app.truearena.api.competitive.RatingService.FinishedGame;
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
import reactor.core.publisher.Flux;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The competitive pipeline against real Postgres + Redis: the SQL (upserts,
 * row locks, partial-index leaderboards, the V32 triggers) is the part that
 * mocks can't meaningfully test.
 *
 * <p>Same Testcontainers rig as {@link ChampionshipServiceIT}. Where
 * Testcontainers can't start containers, point it at an existing, EMPTY
 * database instead — Flyway migrates it from scratch:
 * <pre>
 *   ./mvnw -pl ta-app verify -Dit.test=CompetitiveRatingIT \
 *     -Dit.r2dbc.url=r2dbc:postgresql://localhost:5433/scratch -Dit.jdbc.url=jdbc:postgresql://localhost:5433/scratch \
 *     -Dit.db.user=truearena -Dit.db.password=truearena -Dit.redis.port=6380 -Dit.redis.database=15
 * </pre>
 */
@SpringBootTest
@Tag("integration")
class CompetitiveRatingIT {

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

    @Autowired RatingService ratings;
    @Autowired LeaderboardService leaderboards;
    @Autowired CompetitiveProfileService profiles;
    @Autowired UserRepository users;
    @Autowired DatabaseClient db;

    // ---------------------------------------------------------------- fixtures

    private UUID human(String tag) {
        String unique = (tag + UUID.randomUUID()).replace("-", "").substring(0, 20);
        return users.save(UserRow.newUser(null, unique + "@competitive.test", "Player " + tag, "c_" + unique))
                .map(UserRow::id).block();
    }

    private UUID agent() {
        String unique = UUID.randomUUID().toString().replace("-", "").substring(0, 16);
        return users.save(UserRow.newBot("Agent", "a_" + unique, null, "draughts", "easy")).map(UserRow::id).block();
    }

    /** A finished-game session in a room, the way the orchestrator leaves one. */
    private UUID session(UUID host, boolean ranked) {
        UUID room = db.sql("INSERT INTO rooms (code, host_id, game_type, ranked) VALUES (:code, :host, 'draughts', :ranked) RETURNING id")
                .bind("code", UUID.randomUUID().toString().substring(0, 8)).bind("host", host).bind("ranked", ranked)
                .map(row -> row.get("id", UUID.class)).one().block();
        return db.sql("INSERT INTO game_sessions (room_id, game_type, config, catalog_version, rng_seed, started_at) "
                        + "VALUES (:room, 'draughts', '{}'::jsonb, 1, 1, now() - interval '5 minutes') RETURNING id")
                .bind("room", room).map(row -> row.get("id", UUID.class)).one().block();
    }

    private UUID roomOf(UUID session) {
        return db.sql("SELECT room_id FROM game_sessions WHERE id = :s").bind("s", session)
                .map(row -> row.get("room_id", UUID.class)).one().block();
    }

    private void play(UUID session, UUID winner, UUID loser) {
        ratings.recordMatch(new FinishedGame(session, roomOf(session), "draughts", winner.toString(),
                Map.of(winner.toString(), "won", loser.toString(), "lost"),
                Set.of(winner.toString(), loser.toString()))).block();
    }

    private Map<String, Object> rating(UUID user) {
        return db.sql("SELECT rating, rating_deviation, rated_games_played, provisional, leaderboard_eligible, peak_rating "
                        + "FROM player_game_ratings WHERE user_id = :u AND game_type = 'draughts'")
                .bind("u", user).fetch().one().block();
    }

    private Map<String, Object> stats(UUID user) {
        return db.sql("SELECT * FROM player_game_stats WHERE user_id = :u AND game_type = 'draughts'")
                .bind("u", user).fetch().one().block();
    }

    /** Puts a player straight onto the boards at a chosen rating — for leaderboard-shape tests. */
    private void seedRated(UUID user, double rating, int games, String country, String region) {
        if (country != null) {
            var insert = db.sql("INSERT INTO competitive_profiles (user_id, country_code, country_name, region_code, region_name) "
                            + "VALUES (:u, :c, 'X', :r, 'X')")
                    .bind("u", user).bind("c", country);
            insert = region == null ? insert.bindNull("r", String.class) : insert.bind("r", region);
            insert.fetch().rowsUpdated().block();
        }
        db.sql("INSERT INTO player_game_ratings (user_id, game_type, rating, rating_deviation, peak_rating, "
                        + "rated_games_played, provisional, leaderboard_eligible, country_code, region_code) "
                        + "SELECT :u, :g, :rating, 60, :rating, :n, false, true, p.country_code, p.region_code "
                        + "FROM (SELECT 1) one LEFT JOIN competitive_profiles p ON p.user_id = :u")
                .bind("u", user).bind("g", gameType).bind("rating", rating).bind("n", games)
                .fetch().rowsUpdated().block();
    }

    /**
     * Each leaderboard test gets its own game type so boards don't bleed into
     * each other across tests sharing one database. Rating rows are just rows —
     * the leaderboard has no idea which game types are "real".
     */
    private String gameType = "draughts";

    // ---------------------------------------------------------------- PlayHuud number

    @Test
    void concurrentSignupsGetDistinctSequentialNumbersAndBotsGetNone() {
        List<UUID> ids = Flux.range(0, 25).parallel().runOn(reactor.core.scheduler.Schedulers.parallel())
                .flatMap(i -> users.save(UserRow.newUser(null, "seq" + i + UUID.randomUUID() + "@t.test",
                        "Seq", "s_" + UUID.randomUUID().toString().replace("-", "").substring(0, 18))))
                .map(UserRow::id).sequential().collectList().block();

        List<Long> numbers = Flux.fromIterable(ids).flatMap(users::playhuudNumberOf).collectList().block();
        assertThat(numbers).hasSize(25).doesNotHaveDuplicates().allMatch(n -> n > 0);

        assertThat(users.playhuudNumberOf(agent()).blockOptional()).isEmpty();
    }

    @Test
    void numberSurvivesProfileSaves() {
        UUID id = human("keep");
        long before = users.playhuudNumberOf(id).block();
        UserRow row = users.findById(id).block();
        users.save(row.withProfile("c_renamed_" + before, "🦁")).block();
        assertThat(users.playhuudNumberOf(id).block()).isEqualTo(before);
    }

    // ---------------------------------------------------------------- the rating pipeline

    @Test
    void rankedMatchMovesBothRatingsAndRecordsTheHistory() {
        UUID ada = human("ada");
        UUID bola = human("bola");
        UUID session = session(ada, true);

        play(session, ada, bola);

        Map<String, Object> winner = rating(ada);
        Map<String, Object> loser = rating(bola);
        assertThat((Double) winner.get("rating")).isGreaterThan(1500.0);
        assertThat((Double) loser.get("rating")).isLessThan(1500.0);
        assertThat((Double) winner.get("rating_deviation")).isLessThan(350.0);
        assertThat(winner.get("rated_games_played")).isEqualTo(1);
        assertThat(winner.get("provisional")).isEqualTo(true);
        assertThat(winner.get("leaderboard_eligible")).isEqualTo(false);
        assertThat((Double) winner.get("peak_rating")).isEqualTo((Double) winner.get("rating"));

        Map<String, Object> participant = db.sql("SELECT p.* FROM match_participants p JOIN match_records m "
                        + "ON m.id = p.match_id WHERE m.game_session_id = :s AND p.user_id = :u")
                .bind("s", session).bind("u", ada).fetch().one().block();
        assertThat(participant.get("outcome")).isEqualTo("won");
        assertThat(participant.get("rating_before")).isEqualTo(1500.0);
        assertThat((Double) participant.get("rating_delta")).isPositive();
        assertThat(participant.get("opponent_rating_before")).isEqualTo(1500.0);

        assertThat(stats(ada)).containsEntry("games_played", 1).containsEntry("wins", 1)
                .containsEntry("current_win_streak", 1).containsEntry("best_win_streak", 1);
        assertThat(stats(bola)).containsEntry("losses", 1).containsEntry("current_win_streak", 0);

        Long achievements = db.sql("SELECT count(*) FROM player_achievements WHERE user_id = :u AND type = 'FIRST_RANKED_WIN'")
                .bind("u", ada).map(row -> row.get(0, Long.class)).one().block();
        assertThat(achievements).isEqualTo(1L);
    }

    @Test
    void replayingTheSameSessionNeverAppliesTheRatingTwice() {
        UUID ada = human("ada");
        UUID bola = human("bola");
        UUID session = session(ada, true);

        play(session, ada, bola);
        double afterFirst = (Double) rating(ada).get("rating");
        play(session, ada, bola);

        assertThat(rating(ada)).containsEntry("rated_games_played", 1).containsEntry("rating", afterFirst);
        assertThat(stats(ada)).containsEntry("games_played", 1);
    }

    @Test
    void casualMatchIsRecordedButMovesNoRating() {
        UUID ada = human("ada");
        UUID bola = human("bola");
        UUID session = session(ada, false);

        play(session, ada, bola);

        assertThat(rating(ada)).isNull();
        assertThat(stats(ada)).containsEntry("games_played", 0).containsEntry("casual_games", 1);
        Map<String, Object> match = db.sql("SELECT ranked, unranked_reason FROM match_records WHERE game_session_id = :s")
                .bind("s", session).fetch().one().block();
        assertThat(match).containsEntry("ranked", false).containsEntry("unranked_reason", "casual_room");
    }

    @Test
    void aMatchAgainstACyberAgentIsUnratedEvenInARankedRoom() {
        UUID ada = human("ada");
        UUID bot = agent();
        UUID session = session(ada, true);

        play(session, ada, bot);

        assertThat(rating(ada)).isNull();
        Map<String, Object> match = db.sql("SELECT unranked_reason, player_count FROM match_records WHERE game_session_id = :s")
                .bind("s", session).fetch().one().block();
        assertThat(match).containsEntry("unranked_reason", "vs_agent").containsEntry("player_count", 2);
    }

    @Test
    void farmingTheSameOpponentStopsCountingAfterTheDailyCap() {
        UUID ada = human("ada");
        UUID alt = human("alt");
        for (int i = 0; i < 7; i++) {
            play(session(ada, true), ada, alt);
        }
        assertThat(rating(ada)).containsEntry("rated_games_played", 5);
        Long capped = db.sql("SELECT count(*) FROM match_records m JOIN match_participants p ON p.match_id = m.id "
                        + "WHERE p.user_id = :u AND m.unranked_reason = 'repeat_opponent'")
                .bind("u", ada).map(row -> row.get(0, Long.class)).one().block();
        assertThat(capped).isEqualTo(2L);
    }

    @Test
    void placementGamesThenEligibilityThenARank() {
        UUID ada = human("ada");
        for (int i = 0; i < 10; i++) {
            // Ten different opponents, so the repeat-opponent cap doesn't interfere.
            play(session(ada, true), ada, human("opp" + i));
        }
        assertThat(rating(ada)).containsEntry("rated_games_played", 10)
                .containsEntry("provisional", false).containsEntry("leaderboard_eligible", true);
        assertThat(stats(ada)).containsEntry("current_win_streak", 10).containsEntry("best_win_streak", 10);

        CompetitiveProfileView profile = profiles.profileOf(ada, true).block();
        var draughts = profile.games().getFirst();
        assertThat(draughts.provisional()).isFalse();
        assertThat(draughts.ranks().global().status()).isEqualTo("ranked");
        assertThat(draughts.ranks().global().rank()).isPositive();
        assertThat(draughts.ranks().country().status()).isEqualTo("location_required");
        assertThat(profile.achievements()).extracting(a -> a.type()).contains("STREAK_10", "WINS_10");
    }

    // ---------------------------------------------------------------- leaderboards

    @Test
    void boardsOrderByRatingAndScopeByLocation() {
        gameType = "lb_" + UUID.randomUUID().toString().substring(0, 8);
        UUID top = human("top");
        UUID lagos = human("lagos");
        UUID rivers = human("rivers");
        UUID ghana = human("ghana");
        UUID noLocation = human("nowhere");
        seedRated(top, 2100, 40, "NG", "NG-RI");
        seedRated(lagos, 1900, 40, "NG", "NG-LA");
        seedRated(rivers, 1800, 40, "NG", "NG-RI");
        seedRated(ghana, 2000, 40, "GH", "GH-AA");
        seedRated(noLocation, 1950, 40, null, null);

        LeaderboardView global = leaderboards.page(gameType, LeaderboardScope.GLOBAL, null, rivers, 10, 0).block();
        assertThat(global.entries()).extracting(e -> e.userId()).containsExactly(top, ghana, noLocation, lagos, rivers);
        assertThat(global.me().rank()).isEqualTo(5);

        LeaderboardView nigeria = leaderboards.page(gameType, LeaderboardScope.COUNTRY, null, rivers, 10, 0).block();
        assertThat(nigeria.scopeKey()).isEqualTo("NG");
        assertThat(nigeria.scopeName()).isEqualTo("Nigeria");
        assertThat(nigeria.entries()).extracting(e -> e.userId()).containsExactly(top, lagos, rivers);
        assertThat(nigeria.me().rank()).isEqualTo(3);

        LeaderboardView riversState = leaderboards.page(gameType, LeaderboardScope.REGION, null, rivers, 10, 0).block();
        assertThat(riversState.scopeName()).isEqualTo("Rivers");
        assertThat(riversState.entries()).extracting(e -> e.userId()).containsExactly(top, rivers);
        assertThat(riversState.me().rank()).isEqualTo(2);

        // Browsing someone else's country explicitly.
        LeaderboardView ghanaBoard = leaderboards.page(gameType, LeaderboardScope.COUNTRY, "gh", rivers, 10, 0).block();
        assertThat(ghanaBoard.entries()).extracting(e -> e.userId()).containsExactly(ghana);

        // No location: the scoped boards say why rather than showing someone else's.
        LeaderboardView none = leaderboards.page(gameType, LeaderboardScope.COUNTRY, null, noLocation, 10, 0).block();
        assertThat(none.unavailableReason()).isEqualTo("location_required");
        assertThat(none.entries()).isEmpty();

        // Paging is stable and contiguous.
        LeaderboardView page2 = leaderboards.page(gameType, LeaderboardScope.GLOBAL, null, rivers, 2, 2).block();
        assertThat(page2.entries()).extracting(e -> e.rank()).containsExactly(3, 4);
        assertThat(page2.entries()).extracting(e -> e.userId()).containsExactly(noLocation, lagos);
    }

    @Test
    void tiesBreakDeterministicallyOnExperienceThenId() {
        gameType = "lb_" + UUID.randomUUID().toString().substring(0, 8);
        UUID veteran = human("vet");
        UUID rookieA = human("ra");
        UUID rookieB = human("rb");
        seedRated(veteran, 1842, 90, "NG", "NG-LA");
        seedRated(rookieA, 1842, 20, "NG", "NG-LA");
        seedRated(rookieB, 1842, 20, "NG", "NG-LA");
        // Postgres orders uuids bytewise, which matches their string form — not
        // UUID.compareTo, which compares signed longs.
        UUID firstRookie = rookieA.toString().compareTo(rookieB.toString()) < 0 ? rookieA : rookieB;

        LeaderboardView board = leaderboards.page(gameType, LeaderboardScope.GLOBAL, null, firstRookie, 10, 0).block();
        assertThat(board.entries().getFirst().userId()).isEqualTo(veteran);
        assertThat(board.entries().get(1).userId()).isEqualTo(firstRookie);
        // The pinned "me" rank agrees with the row's position on the page.
        assertThat(board.me().rank()).isEqualTo(2);
    }

    @Test
    void movingAProfileMovesThePlayerBetweenBoards() {
        gameType = "lb_" + UUID.randomUUID().toString().substring(0, 8);
        UUID mover = human("mover");
        seedRated(mover, 1700, 30, "NG", "NG-LA");

        profiles.updateLocation(mover, new UpdateLocationRequest("NG", "NG-RI", null, null, null, null)).block();

        LeaderboardView rivers = leaderboards.page(gameType, LeaderboardScope.REGION, "NG-RI", null, 10, 0).block();
        assertThat(rivers.entries()).extracting(e -> e.userId()).contains(mover);
        LeaderboardView lagos = leaderboards.page(gameType, LeaderboardScope.REGION, "NG-LA", null, 10, 0).block();
        assertThat(lagos.entries()).extracting(e -> e.userId()).doesNotContain(mover);
    }

    @Test
    void friendsBoardIncludesYouAndAcceptedFriendsOnly() {
        gameType = "lb_" + UUID.randomUUID().toString().substring(0, 8);
        UUID me = human("me");
        UUID friend = human("friend");
        UUID pending = human("pending");
        UUID stranger = human("stranger");
        for (UUID u : List.of(me, friend, pending, stranger)) seedRated(u, 1600, 20, null, null);
        friendship(me, friend, "accepted");
        friendship(me, pending, "pending");

        LeaderboardView board = leaderboards.page(gameType, LeaderboardScope.FRIENDS, null, me, 10, 0).block();
        assertThat(board.entries()).extracting(e -> e.userId()).containsExactlyInAnyOrder(me, friend);
        assertThat(board.me()).isNotNull();
    }

    private void friendship(UUID a, UUID b, String status) {
        UUID low = app.truearena.persistence.FriendRow.lowerOf(a, b);
        UUID high = low.equals(a) ? b : a;
        db.sql("INSERT INTO friends (low_user_id, high_user_id, status, requested_by) VALUES (:l, :h, :s, :l)")
                .bind("l", low).bind("h", high).bind("s", status).fetch().rowsUpdated().block();
    }

    // ---------------------------------------------------------------- profile + location control

    @Test
    void profileCarriesNumberFoundingStatusAndLocation() {
        UUID ada = human("ada");
        CompetitiveProfileView before = profiles.profileOf(ada, true).block();
        assertThat(before.playhuudNumber()).isPositive();
        assertThat(before.playhuudId()).matches("#\\d{6,}");
        assertThat(before.profileComplete()).isFalse();
        assertThat(before.location()).isNull();

        CompetitiveProfileView after = profiles.updateLocation(ada,
                new UpdateLocationRequest("ng", "ng-ri", null, "Port Harcourt", false, null)).block();
        assertThat(after.profileComplete()).isTrue();
        assertThat(after.location().countryName()).isEqualTo("Nigeria");
        assertThat(after.location().regionName()).isEqualTo("Rivers");
        assertThat(after.location().city()).isEqualTo("Port Harcourt");

        // City is private unless opted in.
        CompetitiveProfileView publicView = profiles.profileOf(ada, false).block();
        assertThat(publicView.location().city()).isNull();
        assertThat(publicView.location().regionName()).isEqualTo("Rivers");
    }

    @Test
    void locationSwitchingIsRateLimited() {
        UUID ada = human("ada");
        profiles.updateLocation(ada, new UpdateLocationRequest("NG", "NG-RI", null, null, null, null)).block();
        // First correction: allowed, starts the cooldown.
        CompetitiveProfileView corrected = profiles.updateLocation(ada,
                new UpdateLocationRequest("NG", "NG-LA", null, null, null, null)).block();
        assertThat(corrected.locationLockedUntil()).isNotNull();
        // Second change inside the cooldown: refused.
        assertThatThrownBy(() -> profiles.updateLocation(ada,
                new UpdateLocationRequest("GH", "GH-AA", null, null, null, null)).block())
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("change your ranking location again");
        // City alone is never rate-limited.
        assertThat(profiles.updateLocation(ada, new UpdateLocationRequest(null, null, null, "Ikeja", true, null)).block()
                .location().city()).isEqualTo("Ikeja");
    }

    @Test
    void profilesArePublicByDefaultAndCanBeMadePrivate() {
        UUID ada = human("ada");
        UUID bola = human("bola");
        profiles.updateLocation(ada, new UpdateLocationRequest("NG", "NG-RI", null, null, null, null)).block();
        play(session(ada, true), ada, bola);
        String adaName = users.findById(ada).block().username();

        CompetitiveProfileView seen = profiles.profileOfUsername(adaName, bola).block();
        assertThat(seen.profilePublic()).isTrue();
        assertThat(seen.restricted()).isFalse();
        assertThat(seen.games()).isNotEmpty();

        profiles.updateLocation(ada, new UpdateLocationRequest(null, null, null, null, null, false)).block();

        CompetitiveProfileView hidden = profiles.profileOfUsername(adaName, bola).block();
        assertThat(hidden.restricted()).isTrue();
        assertThat(hidden.playhuudId()).isNotNull(); // identity stays
        assertThat(hidden.games()).isEmpty();
        assertThat(hidden.location()).isNull();
        // The owner still sees everything.
        CompetitiveProfileView own = profiles.profileOfUsername(adaName, ada).block();
        assertThat(own.restricted()).isFalse();
        assertThat(own.profilePublic()).isFalse();
        assertThat(own.games()).isNotEmpty();
    }

    @Test
    void matchHistoryShowsDeltasAndOpponents() {
        UUID ada = human("ada");
        UUID bola = human("bola");
        play(session(ada, true), ada, bola);
        play(session(ada, false), bola, ada);

        var history = profiles.matchesOf(ada, "draughts", 10).block();
        assertThat(history).hasSize(2);
        assertThat(history.getFirst().ranked()).isFalse();
        assertThat(history.getFirst().ratingDelta()).isNull();
        assertThat(history.get(1).ranked()).isTrue();
        assertThat(history.get(1).ratingDelta()).isPositive();
        assertThat(history.get(1).opponents()).singleElement()
                .satisfies(o -> assertThat(o.userId()).isEqualTo(bola));
    }
}
