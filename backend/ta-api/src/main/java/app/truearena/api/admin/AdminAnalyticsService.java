package app.truearena.api.admin;

import app.truearena.api.admin.AdminDtos.GameTypeBreakdown;
import app.truearena.api.admin.AdminDtos.IssueEventView;
import app.truearena.api.admin.AdminDtos.IssueFeedRow;
import app.truearena.api.admin.AdminDtos.IssuePage;
import app.truearena.api.admin.AdminDtos.IssueTypeCount;
import app.truearena.api.admin.AdminDtos.LoginEventView;
import app.truearena.api.admin.AdminDtos.Overview;
import app.truearena.api.admin.AdminDtos.RecentGame;
import app.truearena.api.admin.AdminDtos.RetentionDay;
import app.truearena.api.admin.AdminDtos.UserDetail;
import app.truearena.api.admin.AdminDtos.UserPage;
import app.truearena.api.support.ApiExceptions;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Every query here is read-only aggregate SQL against tables the app already writes
 * (users, login_events, issue_events, game_sessions, game_results, player_stats,
 * coin_transactions) — nothing in this class ever mutates state. Uses {@link
 * DatabaseClient} directly rather than repository method-derivation: the joins/
 * aggregates/window filters needed here don't fit Spring Data's method-name query
 * style, and a hand-written projection is clearer than contorting one that does.
 */
@Service
public class AdminAnalyticsService {

    private static final Map<String, String> USER_SORT_COLUMNS = Map.of(
            "created_at", "u.created_at",
            "games_played", "games_played",
            "coins", "u.coins",
            "last_login", "last_login_at"
    );

    private final DatabaseClient db;

    public AdminAnalyticsService(DatabaseClient db) {
        this.db = db;
    }

    public Mono<Overview> overview() {
        Mono<Map<String, Object>> userCounts = db.sql("""
                SELECT
                  COUNT(*) FILTER (WHERE NOT is_bot) AS total_users,
                  COUNT(*) FILTER (WHERE NOT is_bot AND is_guest) AS total_guests,
                  COUNT(*) FILTER (WHERE NOT is_bot AND NOT is_guest) AS total_verified,
                  COUNT(*) FILTER (WHERE NOT is_bot AND created_at >= now() - interval '1 day') AS new_today,
                  COUNT(*) FILTER (WHERE NOT is_bot AND created_at >= now() - interval '7 day') AS new_7d,
                  COUNT(*) FILTER (WHERE NOT is_bot AND created_at >= now() - interval '30 day') AS new_30d,
                  COALESCE(SUM(coins) FILTER (WHERE NOT is_bot), 0) AS coins_in_circulation,
                  COALESCE(SUM(lifetime_coins) FILTER (WHERE NOT is_bot), 0) AS coins_ever_earned
                FROM users
                """)
                .map((row, meta) -> Map.<String, Object>of(
                        "total_users", row.get("total_users", Long.class),
                        "total_guests", row.get("total_guests", Long.class),
                        "total_verified", row.get("total_verified", Long.class),
                        "new_today", row.get("new_today", Long.class),
                        "new_7d", row.get("new_7d", Long.class),
                        "new_30d", row.get("new_30d", Long.class),
                        "coins_in_circulation", row.get("coins_in_circulation", Long.class),
                        "coins_ever_earned", row.get("coins_ever_earned", Long.class)))
                .one();

        Mono<long[]> activeUsers = db.sql("""
                SELECT
                  COUNT(DISTINCT user_id) FILTER (WHERE created_at >= now() - interval '1 day') AS dau,
                  COUNT(DISTINCT user_id) FILTER (WHERE created_at >= now() - interval '7 day') AS wau,
                  COUNT(DISTINCT user_id) FILTER (WHERE created_at >= now() - interval '30 day') AS mau
                FROM login_events
                """)
                .map((row, meta) -> new long[]{
                        nz(row.get("dau", Long.class)), nz(row.get("wau", Long.class)), nz(row.get("mau", Long.class))})
                .one()
                .defaultIfEmpty(new long[]{0, 0, 0});

        Mono<long[]> games = db.sql("""
                SELECT
                  COUNT(*) FILTER (WHERE ended_at IS NOT NULL) AS total_games,
                  COUNT(*) FILTER (WHERE ended_at >= now() - interval '1 day') AS games_today,
                  COUNT(*) FILTER (WHERE ended_at >= now() - interval '7 day') AS games_7d
                FROM game_sessions
                """)
                .map((row, meta) -> new long[]{
                        nz(row.get("total_games", Long.class)), nz(row.get("games_today", Long.class)),
                        nz(row.get("games_7d", Long.class))})
                .one()
                .defaultIfEmpty(new long[]{0, 0, 0});

        Mono<Long> coinsSpent = db.sql("SELECT COALESCE(SUM(-delta), 0) AS spent FROM coin_transactions WHERE delta < 0")
                .map((row, meta) -> nz(row.get("spent", Long.class)))
                .one()
                .defaultIfEmpty(0L);

        Mono<long[]> issueCounts = db.sql("""
                SELECT
                  COUNT(*) FILTER (WHERE created_at >= now() - interval '1 day') AS issues_24h,
                  COUNT(*) FILTER (WHERE created_at >= now() - interval '7 day') AS issues_7d
                FROM issue_events
                """)
                .map((row, meta) -> new long[]{
                        nz(row.get("issues_24h", Long.class)), nz(row.get("issues_7d", Long.class))})
                .one()
                .defaultIfEmpty(new long[]{0, 0});

        Mono<double[]> retention = db.sql("""
                SELECT
                  COUNT(*) FILTER (WHERE u.created_at <= now() - interval '1 day') AS eligible_d1,
                  COUNT(*) FILTER (WHERE u.created_at <= now() - interval '1 day' AND EXISTS (
                      SELECT 1 FROM login_events le WHERE le.user_id = u.id AND le.created_at >= u.created_at + interval '1 day'
                  )) AS returned_d1,
                  COUNT(*) FILTER (WHERE u.created_at <= now() - interval '7 day') AS eligible_d7,
                  COUNT(*) FILTER (WHERE u.created_at <= now() - interval '7 day' AND EXISTS (
                      SELECT 1 FROM login_events le WHERE le.user_id = u.id AND le.created_at >= u.created_at + interval '7 day'
                  )) AS returned_d7
                FROM users u
                WHERE NOT u.is_bot
                """)
                .map((row, meta) -> ratioPair(
                        nz(row.get("returned_d1", Long.class)), nz(row.get("eligible_d1", Long.class)),
                        nz(row.get("returned_d7", Long.class)), nz(row.get("eligible_d7", Long.class))))
                .one()
                .defaultIfEmpty(new double[]{0, 0});

        Flux<GameTypeBreakdown> gameTypes = db.sql("""
                SELECT game_type,
                       COUNT(*) AS sessions,
                       COUNT(*) FILTER (WHERE ended_at IS NOT NULL) AS completed,
                       COALESCE(AVG(EXTRACT(EPOCH FROM (ended_at - started_at)))
                           FILTER (WHERE ended_at IS NOT NULL AND started_at IS NOT NULL), 0) AS avg_seconds
                FROM game_sessions
                GROUP BY game_type
                ORDER BY sessions DESC
                """)
                .map((row, meta) -> new GameTypeBreakdown(
                        row.get("game_type", String.class),
                        nz(row.get("sessions", Long.class)),
                        nz(row.get("completed", Long.class)),
                        row.get("avg_seconds", Double.class) == null ? 0 : row.get("avg_seconds", Double.class)))
                .all();

        Flux<IssueTypeCount> issuesByType = db.sql("""
                SELECT type, COUNT(*) AS cnt FROM issue_events
                WHERE created_at >= now() - interval '30 day'
                GROUP BY type ORDER BY cnt DESC LIMIT 10
                """)
                .map((row, meta) -> new IssueTypeCount(row.get("type", String.class), nz(row.get("cnt", Long.class))))
                .all();

        return Mono.zip(userCounts, activeUsers, games, coinsSpent, issueCounts, retention)
                .flatMap(t -> Mono.zip(gameTypes.collectList(), issuesByType.collectList())
                        .map(lists -> {
                            Map<String, Object> uc = t.getT1();
                            long[] au = t.getT2();
                            long[] g = t.getT3();
                            long spent = t.getT4();
                            long[] ic = t.getT5();
                            double[] ret = t.getT6();
                            return new Overview(
                                    (long) uc.get("total_users"), (long) uc.get("total_guests"), (long) uc.get("total_verified"),
                                    (long) uc.get("new_today"), (long) uc.get("new_7d"), (long) uc.get("new_30d"),
                                    au[0], au[1], au[2],
                                    ret[0], ret[1],
                                    g[0], g[1], g[2],
                                    (long) uc.get("coins_in_circulation"), (long) uc.get("coins_ever_earned"), spent,
                                    ic[0], ic[1],
                                    lists.getT1(), lists.getT2());
                        }));
    }

    public Mono<UserPage> users(int page, int size, String query, String sort) {
        int boundedSize = Math.min(Math.max(size, 1), 200);
        int boundedPage = Math.max(page, 0);
        String q = query == null ? "" : query.trim();
        String orderBy = USER_SORT_COLUMNS.getOrDefault(sort == null ? "" : sort, "u.created_at");

        String sql = """
                SELECT u.id, u.display_name, u.username, u.phone, u.email, u.is_guest, u.created_at,
                       u.coins, u.lifetime_coins,
                       (SELECT MAX(created_at) FROM login_events le WHERE le.user_id = u.id) AS last_login_at,
                       (SELECT COUNT(*) FROM login_events le WHERE le.user_id = u.id) AS login_count,
                       COALESCE(ps.games_played, 0) AS games_played,
                       COALESCE(ps.wins, 0) AS wins,
                       (SELECT COALESCE(SUM(-delta), 0) FROM coin_transactions ct
                            WHERE ct.user_id = u.id AND ct.delta < 0) AS coins_spent,
                       (SELECT COALESCE(SUM(delta), 0) FROM coin_transactions ct
                            WHERE ct.user_id = u.id AND ct.reason LIKE 'match_stake_%') AS stake_net,
                       (SELECT COUNT(*) FROM issue_events ie WHERE ie.user_id = u.id) AS issues_count
                FROM users u
                LEFT JOIN player_stats ps ON ps.user_id = u.id AND ps.group_id IS NULL
                WHERE NOT u.is_bot
                  AND (:q = '' OR u.display_name ILIKE '%' || :q || '%' OR u.username ILIKE '%' || :q || '%'
                       OR u.phone ILIKE '%' || :q || '%' OR u.email ILIKE '%' || :q || '%')
                ORDER BY __ORDER_COL__ DESC NULLS LAST
                LIMIT :limit OFFSET :offset
                """.replace("__ORDER_COL__", orderBy);

        Flux<AdminDtos.UserRow> rows = db.sql(sql)
                .bind("q", q)
                .bind("limit", boundedSize)
                .bind("offset", boundedPage * boundedSize)
                .map((row, meta) -> toUserRow(row))
                .all();

        Mono<Long> total = db.sql("""
                SELECT COUNT(*) AS cnt FROM users u
                WHERE NOT u.is_bot
                  AND (:q = '' OR u.display_name ILIKE '%' || :q || '%' OR u.username ILIKE '%' || :q || '%'
                       OR u.phone ILIKE '%' || :q || '%' OR u.email ILIKE '%' || :q || '%')
                """)
                .bind("q", q)
                .map((row, meta) -> nz(row.get("cnt", Long.class)))
                .one()
                .defaultIfEmpty(0L);

        return Mono.zip(rows.collectList(), total)
                .map(t -> new UserPage(t.getT1(), t.getT2(), boundedPage, boundedSize));
    }

    public Mono<UserDetail> userDetail(UUID userId) {
        Mono<AdminDtos.UserRow> summary = db.sql("""
                SELECT u.id, u.display_name, u.username, u.phone, u.email, u.is_guest, u.created_at,
                       u.coins, u.lifetime_coins,
                       (SELECT MAX(created_at) FROM login_events le WHERE le.user_id = u.id) AS last_login_at,
                       (SELECT COUNT(*) FROM login_events le WHERE le.user_id = u.id) AS login_count,
                       COALESCE(ps.games_played, 0) AS games_played,
                       COALESCE(ps.wins, 0) AS wins,
                       (SELECT COALESCE(SUM(-delta), 0) FROM coin_transactions ct
                            WHERE ct.user_id = u.id AND ct.delta < 0) AS coins_spent,
                       (SELECT COALESCE(SUM(delta), 0) FROM coin_transactions ct
                            WHERE ct.user_id = u.id AND ct.reason LIKE 'match_stake_%') AS stake_net,
                       (SELECT COUNT(*) FROM issue_events ie WHERE ie.user_id = u.id) AS issues_count
                FROM users u
                LEFT JOIN player_stats ps ON ps.user_id = u.id AND ps.group_id IS NULL
                WHERE u.id = :id
                """)
                .bind("id", userId)
                .map((row, meta) -> toUserRow(row))
                .one()
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such user")));

        Flux<LoginEventView> logins = db.sql(
                "SELECT created_at, method FROM login_events WHERE user_id = :id ORDER BY created_at DESC LIMIT 20")
                .bind("id", userId)
                .map((row, meta) -> new LoginEventView(row.get("created_at", Instant.class), row.get("method", String.class)))
                .all();

        Flux<RecentGame> games = db.sql("""
                SELECT gs.id, gs.game_type, gs.started_at, gs.ended_at, gr.winning_side
                FROM room_members rm
                JOIN game_sessions gs ON gs.room_id = rm.room_id
                LEFT JOIN game_results gr ON gr.game_session_id = gs.id
                WHERE rm.user_id = :id
                ORDER BY gs.started_at DESC NULLS LAST
                LIMIT 20
                """)
                .bind("id", userId)
                .map((row, meta) -> new RecentGame(
                        row.get("id", UUID.class), row.get("game_type", String.class),
                        row.get("started_at", Instant.class), row.get("ended_at", Instant.class),
                        row.get("winning_side", String.class)))
                .all();

        Flux<IssueEventView> issues = db.sql(
                "SELECT created_at, type, detail FROM issue_events WHERE user_id = :id ORDER BY created_at DESC LIMIT 20")
                .bind("id", userId)
                .map((row, meta) -> new IssueEventView(
                        row.get("created_at", Instant.class), row.get("type", String.class), row.get("detail", String.class)))
                .all();

        return Mono.zip(summary, logins.collectList(), games.collectList(), issues.collectList())
                .map(t -> new UserDetail(t.getT1(), t.getT2(), t.getT3(), t.getT4()));
    }

    public Mono<IssuePage> issues(int page, int size, String type) {
        int boundedSize = Math.min(Math.max(size, 1), 200);
        int boundedPage = Math.max(page, 0);
        String t = type == null ? "" : type.trim();

        Flux<IssueFeedRow> rows = db.sql("""
                SELECT ie.created_at, ie.type, ie.detail, ie.user_id, u.display_name
                FROM issue_events ie
                LEFT JOIN users u ON u.id = ie.user_id
                WHERE (:type = '' OR ie.type = :type)
                ORDER BY ie.created_at DESC
                LIMIT :limit OFFSET :offset
                """)
                .bind("type", t)
                .bind("limit", boundedSize)
                .bind("offset", boundedPage * boundedSize)
                .map((row, meta) -> new IssueFeedRow(
                        row.get("created_at", Instant.class), row.get("type", String.class), row.get("detail", String.class),
                        row.get("user_id", UUID.class), row.get("display_name", String.class)))
                .all();

        Mono<Long> total = db.sql("SELECT COUNT(*) AS cnt FROM issue_events WHERE (:type = '' OR type = :type)")
                .bind("type", t)
                .map((row, meta) -> nz(row.get("cnt", Long.class)))
                .one()
                .defaultIfEmpty(0L);

        return Mono.zip(rows.collectList(), total)
                .map(res -> new IssuePage(res.getT1(), res.getT2(), boundedPage, boundedSize));
    }

    /** Daily signup cohorts for the last {@code days} days, each with its D1/D7 return rate —
     * {@code null} when a cohort isn't old enough yet to have a measurable D1/D7 window. */
    public Flux<RetentionDay> retention(int days) {
        int bounded = Math.min(Math.max(days, 1), 90);
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        return db.sql("""
                SELECT date_trunc('day', created_at) AS cohort_day,
                       COUNT(*) AS new_users,
                       COUNT(*) FILTER (WHERE EXISTS (
                           SELECT 1 FROM login_events le WHERE le.user_id = u.id
                               AND le.created_at >= u.created_at + interval '1 day')) AS returned_d1,
                       COUNT(*) FILTER (WHERE EXISTS (
                           SELECT 1 FROM login_events le WHERE le.user_id = u.id
                               AND le.created_at >= u.created_at + interval '7 day')) AS returned_d7
                FROM users u
                WHERE NOT u.is_bot AND u.created_at >= now() - (:days || ' day')::interval
                GROUP BY cohort_day
                ORDER BY cohort_day
                """)
                .bind("days", bounded)
                .map((row, meta) -> {
                    Instant cohortInstant = row.get("cohort_day", Instant.class);
                    LocalDate cohortDate = cohortInstant.atZone(ZoneOffset.UTC).toLocalDate();
                    long newUsers = nz(row.get("new_users", Long.class));
                    long d1 = nz(row.get("returned_d1", Long.class));
                    long d7 = nz(row.get("returned_d7", Long.class));
                    Double d1Pct = cohortDate.plusDays(1).isAfter(today) || newUsers == 0
                            ? null : 100.0 * d1 / newUsers;
                    Double d7Pct = cohortDate.plusDays(7).isAfter(today) || newUsers == 0
                            ? null : 100.0 * d7 / newUsers;
                    return new RetentionDay(cohortDate.toString(), newUsers, d1Pct, d7Pct);
                })
                .all();
    }

    private static AdminDtos.UserRow toUserRow(io.r2dbc.spi.Row row) {
        int gamesPlayed = row.get("games_played", Integer.class);
        int wins = row.get("wins", Integer.class);
        return new AdminDtos.UserRow(
                row.get("id", UUID.class),
                row.get("display_name", String.class),
                row.get("username", String.class),
                ContactMasker.mask(row.get("phone", String.class), row.get("email", String.class)),
                Boolean.TRUE.equals(row.get("is_guest", Boolean.class)),
                row.get("created_at", Instant.class),
                row.get("last_login_at", Instant.class),
                nz(row.get("login_count", Long.class)),
                gamesPlayed, wins,
                gamesPlayed == 0 ? 0 : (double) wins / gamesPlayed,
                nz(row.get("coins", Long.class)),
                nz(row.get("lifetime_coins", Long.class)),
                nz(row.get("coins_spent", Long.class)),
                nz(row.get("stake_net", Long.class)),
                nz(row.get("issues_count", Long.class)));
    }

    private static long nz(Long v) {
        return v == null ? 0L : v;
    }

    private static double[] ratioPair(long d1, long e1, long d7, long e7) {
        return new double[]{e1 == 0 ? 0 : 100.0 * d1 / e1, e7 == 0 ? 0 : 100.0 * d7 / e7};
    }
}
