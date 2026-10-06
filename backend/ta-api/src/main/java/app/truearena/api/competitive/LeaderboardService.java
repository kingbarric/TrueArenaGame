package app.truearena.api.competitive;

import app.truearena.api.competitive.CompetitiveDtos.FoundingView;
import app.truearena.api.competitive.CompetitiveDtos.LeaderboardEntryView;
import app.truearena.api.competitive.CompetitiveDtos.LeaderboardView;
import app.truearena.api.competitive.CompetitiveDtos.RankView;
import app.truearena.api.competitive.CompetitiveDtos.RanksView;
import app.truearena.persistence.PlayerGameRatingRow;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.r2dbc.spi.Readable;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.List;
import java.util.UUID;

/**
 * Every board for every game, from one query shape. Adding Chess adds rows,
 * not code.
 *
 * <p><b>Performance.</b> Nothing here ever materialises a whole board.
 * Country/region are denormalised onto {@code player_game_ratings} and
 * eligibility is a stored boolean, so a page is a partial-index scan with a
 * LIMIT, and "what's my rank" is an index-only COUNT of rows ahead of you. Both
 * are cached in Redis for {@link #TTL}; a rated match bumps the game's cache
 * version rather than hunting down keys, and stale versions just expire.
 * Redis being unavailable degrades to the database, never to an error.
 *
 * <p>Ordering is {@code rating DESC, rated_games_played DESC, user_id} —
 * competitive rating first, never volume, with a deterministic tiebreak so
 * paging can't show one player twice.
 */
@Service
public class LeaderboardService {

    private static final Logger log = LoggerFactory.getLogger(LeaderboardService.class);

    static final Duration TTL = Duration.ofSeconds(60);
    static final int MAX_PAGE = 50;
    private static final int FRIENDS_LIMIT = 200;

    private static final String ORDER = " ORDER BY r.rating DESC, r.rated_games_played DESC, r.user_id ";

    private static final String ENTRY_COLUMNS =
            "r.user_id, r.rating, r.peak_rating, r.rated_games_played, r.provisional, "
                    + "u.username, u.display_name, u.avatar_url, u.playhuud_number, "
                    + "coalesce(s.games_played, 0) AS games_played, coalesce(s.wins, 0) AS wins, "
                    + "(SELECT count(*) FROM championships c WHERE c.champion_id = r.user_id "
                    + "   AND c.game_type = r.game_type AND c.status = 'completed') AS tournament_wins ";

    private static final String ENTRY_FROM =
            "FROM player_game_ratings r JOIN users u ON u.id = r.user_id "
                    + "LEFT JOIN player_game_stats s ON s.user_id = r.user_id AND s.game_type = r.game_type ";

    private final DatabaseClient db;
    private final ObjectProvider<ReactiveStringRedisTemplate> redisProvider;
    private final ObjectMapper mapper;

    public LeaderboardService(DatabaseClient db, ObjectProvider<ReactiveStringRedisTemplate> redisProvider,
                              ObjectMapper mapper) {
        this.db = db;
        this.redisProvider = redisProvider;
        this.mapper = mapper;
    }

    // ---------------------------------------------------------------- boards

    /**
     * One page of a board. For country/region, {@code scopeKey} picks which
     * one (so a player abroad can still browse Nigeria's board); null means
     * "mine", and is unavailable until the viewer has set that location.
     */
    public Mono<LeaderboardView> page(String gameType, LeaderboardScope scope, String scopeKey, UUID viewer,
                                      int limit, int offset) {
        int pageSize = Math.max(1, Math.min(limit, MAX_PAGE));
        int from = Math.max(0, offset);
        if (scope == LeaderboardScope.FRIENDS) {
            return friendsBoard(gameType, viewer, pageSize, from);
        }
        return resolveScopeKey(scope, scopeKey, viewer).flatMap(key -> {
            if (scope != LeaderboardScope.GLOBAL && key.isEmpty()) {
                return Mono.just(new LeaderboardView(gameType, scope.wire(), null, null, from, List.of(),
                        null, RankView.LOCATION_REQUIRED));
            }
            String k = key.orElse(null);
            Mono<List<LeaderboardEntryView>> entries = cachedPage(gameType, scope, k, pageSize, from);
            Mono<java.util.Optional<LeaderboardEntryView>> me = viewer == null ? Mono.just(java.util.Optional.empty())
                    : ownEntry(gameType, scope, k, viewer).map(java.util.Optional::of)
                    .defaultIfEmpty(java.util.Optional.empty());
            return Mono.zip(entries, me).map(t -> new LeaderboardView(gameType, scope.wire(), k, scopeName(scope, k),
                    from, t.getT1(), t.getT2().orElse(null), null));
        });
    }

    /** All three geographic ranks for one rating row, with the reason when one isn't available. */
    public Mono<RanksView> ranksOf(PlayerGameRatingRow r) {
        if (r == null || r.ratedGamesPlayed() == 0) {
            RankView none = new RankView(null, RankView.UNRATED);
            return Mono.just(new RanksView(none, none, none));
        }
        if (!r.leaderboardEligible()) {
            RankView provisional = new RankView(null, RankView.PROVISIONAL);
            return Mono.just(new RanksView(provisional,
                    r.countryCode() == null ? new RankView(null, RankView.LOCATION_REQUIRED) : provisional,
                    r.regionCode() == null ? new RankView(null, RankView.LOCATION_REQUIRED) : provisional));
        }
        return Mono.zip(
                rankView(r, LeaderboardScope.GLOBAL, null),
                rankView(r, LeaderboardScope.COUNTRY, r.countryCode()),
                rankView(r, LeaderboardScope.REGION, r.regionCode()))
                .map(t -> new RanksView(t.getT1(), t.getT2(), t.getT3()));
    }

    /**
     * The player's current global rank, or empty if they're not on the board.
     * Used before a rating update to decide "defeated a top-100 player".
     */
    public Mono<Integer> globalRankOf(PlayerGameRatingRow r) {
        if (r == null || !r.leaderboardEligible()) return Mono.empty();
        return countAhead(r, LeaderboardScope.GLOBAL, null).map(ahead -> (int) (ahead + 1));
    }

    /**
     * Called after a rated match. Bumping the version orphans every cached page
     * and rank for the game at once; orphans expire on their own TTL.
     */
    public Mono<Void> invalidate(String gameType) {
        ReactiveStringRedisTemplate redis = redisProvider.getIfAvailable();
        if (redis == null) return Mono.empty();
        return redis.opsForValue().increment(versionKey(gameType)).then()
                .onErrorResume(e -> {
                    log.debug("leaderboard cache invalidation skipped: {}", e.toString());
                    return Mono.empty();
                });
    }

    // ---------------------------------------------------------------- internals

    private Mono<RankView> rankView(PlayerGameRatingRow r, LeaderboardScope scope, String key) {
        if (scope != LeaderboardScope.GLOBAL && key == null) {
            return Mono.just(new RankView(null, RankView.LOCATION_REQUIRED));
        }
        String cacheKey = "rank:" + scope.wire() + ":" + (key == null ? "-" : key) + ":" + r.userId();
        return cached(r.gameType(), cacheKey, Long.class, countAhead(r, scope, key))
                .map(ahead -> new RankView((int) (ahead + 1), RankView.RANKED));
    }

    /**
     * How many eligible players on this board sort ahead of {@code r}. The
     * redundant {@code rating >= :rating} is load-bearing: without it the
     * tiebreak OR hides the range from the planner and this becomes a full
     * scan of the board; with it, the cost scales with the number of players
     * ahead of you, not the size of the board (checked with EXPLAIN on 20k rows).
     */
    private Mono<Long> countAhead(PlayerGameRatingRow r, LeaderboardScope scope, String key) {
        String sql = "SELECT count(*) AS ahead FROM player_game_ratings r WHERE r.game_type = :g AND r.leaderboard_eligible "
                + scopeFilter(scope)
                + "AND r.rating >= :rating "
                + "AND (r.rating > :rating OR (r.rating = :rating AND (r.rated_games_played > :n "
                + "     OR (r.rated_games_played = :n AND r.user_id < :uid))))";
        var spec = db.sql(sql).bind("g", r.gameType()).bind("rating", r.rating())
                .bind("n", r.ratedGamesPlayed()).bind("uid", r.userId());
        if (scope != LeaderboardScope.GLOBAL) spec = bindScope(spec, scope, key);
        return spec.map(row -> row.get("ahead", Long.class)).one().defaultIfEmpty(0L);
    }

    private Mono<List<LeaderboardEntryView>> cachedPage(String gameType, LeaderboardScope scope, String key,
                                                       int limit, int offset) {
        String cacheKey = "page:" + scope.wire() + ":" + (key == null ? "-" : key) + ":" + offset + ":" + limit;
        Mono<List<LeaderboardEntryView>> load = queryPage(gameType, scope, key, limit, offset).collectList();
        return cached(gameType, cacheKey, LeaderboardEntryView[].class, load.map(l -> l.toArray(LeaderboardEntryView[]::new)))
                .map(List::of);
    }

    private Flux<LeaderboardEntryView> queryPage(String gameType, LeaderboardScope scope, String key,
                                                 int limit, int offset) {
        String sql = "SELECT " + ENTRY_COLUMNS + ENTRY_FROM
                + "WHERE r.game_type = :g AND r.leaderboard_eligible " + scopeFilter(scope)
                + ORDER + "LIMIT :limit OFFSET :offset";
        var spec = db.sql(sql).bind("g", gameType).bind("limit", limit).bind("offset", offset);
        if (scope != LeaderboardScope.GLOBAL) spec = bindScope(spec, scope, key);
        int[] position = {offset};
        return spec.map(row -> entry(row, 0)).all()
                .map(e -> withRank(e, ++position[0]));
    }

    private Mono<LeaderboardEntryView> ownEntry(String gameType, LeaderboardScope scope, String key, UUID viewer) {
        return db.sql("SELECT " + ENTRY_COLUMNS + ENTRY_FROM + "WHERE r.game_type = :g AND r.user_id = :uid")
                .bind("g", gameType).bind("uid", viewer)
                .map(row -> new Object[]{entry(row, 0), row.get("rating", Double.class),
                        row.get("rated_games_played", Integer.class)})
                .one()
                .flatMap(parts -> {
                    LeaderboardEntryView e = (LeaderboardEntryView) parts[0];
                    PlayerGameRatingRow probe = new PlayerGameRatingRow(null, viewer, gameType, (Double) parts[1],
                            0, 0, 0, (Integer) parts[2], e.provisional(), !e.provisional(), null, null, null, null);
                    if (e.provisional()) return Mono.just(e); // rank 0 = "not on the board yet"
                    return countAhead(probe, scope, key).map(ahead -> withRank(e, (int) (ahead + 1)));
                });
    }

    private Mono<LeaderboardView> friendsBoard(String gameType, UUID viewer, int limit, int offset) {
        if (viewer == null) {
            return Mono.just(new LeaderboardView(gameType, LeaderboardScope.FRIENDS.wire(), null, null, offset,
                    List.of(), null, "sign_in_required"));
        }
        // Bounded by the friend list, not by rating, so the partial indexes don't
        // apply and caching per-viewer buys nothing. Provisional friends are shown
        // (flagged) — "where do I rank among my friends" shouldn't hide half of them.
        String sql = "WITH circle AS ("
                + "  SELECT CAST(:me AS uuid) AS id "
                + "  UNION SELECT CASE WHEN f.low_user_id = :me THEN f.high_user_id ELSE f.low_user_id END "
                + "  FROM friends f WHERE f.status = 'accepted' AND (f.low_user_id = :me OR f.high_user_id = :me)) "
                + "SELECT " + ENTRY_COLUMNS + ENTRY_FROM + "JOIN circle ON circle.id = r.user_id "
                + "WHERE r.game_type = :g AND r.rated_games_played > 0 " + ORDER + "LIMIT :limit";
        int[] position = {0};
        return db.sql(sql).bind("me", viewer).bind("g", gameType).bind("limit", FRIENDS_LIMIT)
                .map(row -> entry(row, 0)).all()
                .map(e -> withRank(e, ++position[0]))
                .collectList()
                .map(all -> {
                    LeaderboardEntryView me = all.stream().filter(e -> e.userId().equals(viewer)).findFirst().orElse(null);
                    List<LeaderboardEntryView> page = all.stream().skip(offset).limit(limit).toList();
                    return new LeaderboardView(gameType, LeaderboardScope.FRIENDS.wire(), null, null, offset, page, me, null);
                });
    }

    private Mono<java.util.Optional<String>> resolveScopeKey(LeaderboardScope scope, String explicit, UUID viewer) {
        if (scope == LeaderboardScope.GLOBAL) return Mono.just(java.util.Optional.empty());
        if (explicit != null && !explicit.isBlank()) {
            return Mono.just(java.util.Optional.of(explicit.trim().toUpperCase(java.util.Locale.ROOT)));
        }
        if (viewer == null) return Mono.just(java.util.Optional.empty());
        String column = scope == LeaderboardScope.COUNTRY ? "country_code" : "region_code";
        return db.sql("SELECT " + column + " AS k FROM competitive_profiles WHERE user_id = :uid")
                .bind("uid", viewer)
                .map(row -> java.util.Optional.ofNullable(row.get("k", String.class)))
                .one()
                .defaultIfEmpty(java.util.Optional.empty());
    }

    private static String scopeName(LeaderboardScope scope, String key) {
        if (key == null) return null;
        if (scope == LeaderboardScope.COUNTRY) {
            return LocationCatalog.country(key).map(LocationCatalog.Country::name).orElse(key);
        }
        if (scope == LeaderboardScope.REGION && key.length() > 3) {
            return LocationCatalog.regions(key.substring(0, 2)).stream()
                    .filter(r -> r.code().equals(key)).map(LocationCatalog.Region::name).findFirst()
                    .orElse(null); // free-text regions: the app shows the viewer's own stored name
        }
        return null;
    }

    private static String scopeFilter(LeaderboardScope scope) {
        return switch (scope) {
            case COUNTRY -> "AND r.country_code = :key ";
            case REGION -> "AND r.country_code = :country AND r.region_code = :key ";
            default -> "";
        };
    }

    private static DatabaseClient.GenericExecuteSpec bindScope(DatabaseClient.GenericExecuteSpec spec,
                                                               LeaderboardScope scope, String key) {
        spec = spec.bind("key", key);
        if (scope == LeaderboardScope.REGION) {
            // Region codes are country-prefixed (NG-RI); binding the country too
            // lets the planner use the (game_type, country_code, region_code) index.
            spec = spec.bind("country", key.length() >= 2 ? key.substring(0, 2) : key);
        }
        return spec;
    }

    private static LeaderboardEntryView entry(Readable row, int rank) {
        Long number = row.get("playhuud_number", Long.class);
        int games = numberOr(row.get("games_played", Integer.class));
        int wins = numberOr(row.get("wins", Integer.class));
        Long tournamentWins = row.get("tournament_wins", Long.class);
        return new LeaderboardEntryView(rank,
                row.get("user_id", UUID.class),
                row.get("username", String.class),
                row.get("display_name", String.class),
                row.get("avatar_url", String.class),
                number,
                FoundingTier.formatNumber(number),
                FoundingView.of(FoundingTier.of(number)),
                (int) Math.round(row.get("rating", Double.class)),
                (int) Math.round(row.get("peak_rating", Double.class)),
                games,
                games == 0 ? 0.0 : (double) wins / games,
                tournamentWins == null ? 0 : tournamentWins.intValue(),
                Boolean.TRUE.equals(row.get("provisional", Boolean.class)));
    }

    private static LeaderboardEntryView withRank(LeaderboardEntryView e, int rank) {
        return new LeaderboardEntryView(rank, e.userId(), e.username(), e.displayName(), e.avatarUrl(),
                e.playhuudNumber(), e.playhuudId(), e.founding(), e.rating(), e.peakRating(), e.gamesPlayed(),
                e.winRate(), e.tournamentWins(), e.provisional());
    }

    private static int numberOr(Integer value) {
        return value == null ? 0 : value;
    }

    // ---------------------------------------------------------------- cache

    private static String versionKey(String gameType) {
        return "lb:ver:" + gameType;
    }

    /**
     * Read-through cache under the game's current version. Any Redis failure —
     * down, timeout, unreadable payload — falls straight through to {@code load}.
     */
    private <T> Mono<T> cached(String gameType, String key, Class<T> type, Mono<T> load) {
        ReactiveStringRedisTemplate redis = redisProvider.getIfAvailable();
        if (redis == null) return load;
        return redis.opsForValue().get(versionKey(gameType)).defaultIfEmpty("0")
                .flatMap(version -> {
                    String full = "lb:" + gameType + ":v" + version + ":" + key;
                    return redis.opsForValue().get(full)
                            .flatMap(json -> Mono.fromCallable(() -> mapper.readValue(json, type)))
                            .switchIfEmpty(Mono.defer(() -> load.flatMap(value -> Mono.fromCallable(() -> mapper.writeValueAsString(value))
                                    .flatMap(json -> redis.opsForValue().set(full, json, TTL))
                                    .onErrorResume(e -> Mono.just(false))
                                    .thenReturn(value))));
                })
                .onErrorResume(e -> {
                    log.debug("leaderboard cache bypassed: {}", e.toString());
                    return load;
                });
    }
}
