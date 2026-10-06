package app.truearena.api.competitive;

import app.truearena.api.competitive.CompetitiveDtos.AchievementView;
import app.truearena.api.competitive.CompetitiveDtos.CompetitiveProfileView;
import app.truearena.api.competitive.CompetitiveDtos.FoundingView;
import app.truearena.api.competitive.CompetitiveDtos.GameRecordView;
import app.truearena.api.competitive.CompetitiveDtos.GameStatsView;
import app.truearena.api.competitive.CompetitiveDtos.LocationView;
import app.truearena.api.competitive.CompetitiveDtos.MatchHistoryView;
import app.truearena.api.competitive.CompetitiveDtos.MatchOpponentView;
import app.truearena.api.competitive.CompetitiveDtos.UpdateLocationRequest;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.CompetitiveProfileRepository;
import app.truearena.persistence.CompetitiveProfileRow;
import app.truearena.persistence.PlayerAchievementRepository;
import app.truearena.persistence.PlayerAchievementRow;
import app.truearena.persistence.PlayerGameRatingRepository;
import app.truearena.persistence.PlayerGameRatingRow;
import app.truearena.persistence.PlayerGameStatsRepository;
import app.truearena.persistence.PlayerGameStatsRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * The player's competitive identity: PlayHuud number, founding status,
 * location, and their record in every rated game — the "gaming CV".
 *
 * <p>Everything here is a read of state the rating pipeline wrote, plus the
 * one thing a player may set themselves: where they compete.
 */
@Service
public class CompetitiveProfileService {

    private final UserRepository users;
    private final CompetitiveProfileRepository profiles;
    private final PlayerGameRatingRepository ratings;
    private final PlayerGameStatsRepository stats;
    private final PlayerAchievementRepository achievements;
    private final LeaderboardService leaderboards;
    private final CompetitiveSettings settings;
    private final LocationChangePolicy locationPolicy;
    private final DatabaseClient db;
    private final ObjectMapper mapper;

    public CompetitiveProfileService(UserRepository users, CompetitiveProfileRepository profiles,
                                     PlayerGameRatingRepository ratings, PlayerGameStatsRepository stats,
                                     PlayerAchievementRepository achievements, LeaderboardService leaderboards,
                                     CompetitiveSettings settings, DatabaseClient db, ObjectMapper mapper) {
        this.users = users;
        this.profiles = profiles;
        this.ratings = ratings;
        this.stats = stats;
        this.achievements = achievements;
        this.leaderboards = leaderboards;
        this.settings = settings;
        this.locationPolicy = new LocationChangePolicy(settings);
        this.db = db;
        this.mapper = mapper;
    }

    // ---------------------------------------------------------------- reads

    public Mono<CompetitiveProfileView> profileOf(UUID userId, boolean own) {
        return users.findById(userId)
                .filter(u -> own || !u.isBot())
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("player not found")))
                .flatMap(user -> profileOf(user, own));
    }

    public Mono<CompetitiveProfileView> profileOfUsername(String username, UUID viewer) {
        return users.findByUsername(username)
                .filter(u -> !u.isBot())
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("player not found")))
                .flatMap(user -> profileOf(user, user.id().equals(viewer)));
    }

    private Mono<CompetitiveProfileView> profileOf(UserRow user, boolean own) {
        Mono<Long> number = users.playhuudNumberOf(user.id()).map(n -> n).defaultIfEmpty(-1L);
        return Mono.zip(number, profiles.findByUserId(user.id()).defaultIfEmpty(CompetitiveProfileRow.empty(user.id())))
                .flatMap(t -> {
                    Long playhuudNumber = t.getT1() < 0 ? null : t.getT1();
                    CompetitiveProfileRow p = t.getT2();
                    FoundingTier tier = FoundingTier.of(playhuudNumber);
                    if (!own && !p.profilePublic()) {
                        // Private: identity only. The PlayHuud number and founding
                        // tier are who you are, not what you've done, so they stay.
                        return Mono.just(new CompetitiveProfileView(
                                user.id(), user.username(), user.displayName(), user.avatarUrl(),
                                playhuudNumber, FoundingTier.formatNumber(playhuudNumber), FoundingView.of(tier),
                                null, false, null, false, true, List.of(), achievementViews(tier, List.of())));
                    }
                    Mono<List<GameRecordView>> games = gameRecords(user.id());
                    Mono<List<PlayerAchievementRow>> earned = achievements
                            .findByUserIdOrderByDisplayPriorityDescEarnedAtDesc(user.id()).collectList();
                    return Mono.zip(games, earned).map(g -> new CompetitiveProfileView(
                            user.id(), user.username(), user.displayName(), user.avatarUrl(),
                            playhuudNumber, FoundingTier.formatNumber(playhuudNumber), FoundingView.of(tier),
                            location(p, own),
                            p.hasCountry() && p.hasRegion(),
                            own && p.locationLockedUntil() != null && p.locationLockedUntil().isAfter(Instant.now())
                                    ? p.locationLockedUntil() : null,
                            p.profilePublic(),
                            false,
                            g.getT1(),
                            achievementViews(tier, g.getT2())));
                });
    }

    /** Whether someone other than the owner may see this player's games and history. */
    public Mono<Boolean> isPublic(UUID userId) {
        return profiles.findByUserId(userId).map(CompetitiveProfileRow::profilePublic).defaultIfEmpty(true);
    }

    /**
     * One record per game the player has touched competitively, strongest
     * rating first. A game with casual play but no rated games still appears
     * (as unrated) so the profile reflects everything they play.
     */
    private Mono<List<GameRecordView>> gameRecords(UUID userId) {
        Mono<Map<String, PlayerGameRatingRow>> ratingRows = ratings.findByUserId(userId)
                .collectMap(PlayerGameRatingRow::gameType);
        Mono<Map<String, PlayerGameStatsRow>> statRows = stats.findByUserId(userId)
                .collectMap(PlayerGameStatsRow::gameType);
        Mono<Map<String, Long>> tournamentWins = db.sql("SELECT game_type, count(*) AS n FROM championships "
                        + "WHERE champion_id = :uid AND status = 'completed' GROUP BY game_type")
                .bind("uid", userId)
                .map(row -> Map.entry(row.get("game_type", String.class), row.get("n", Long.class)))
                .all().collectMap(Map.Entry::getKey, Map.Entry::getValue);

        return Mono.zip(ratingRows, statRows, tournamentWins).flatMap(t -> {
            Set<String> gameTypes = new LinkedHashSet<>(t.getT1().keySet());
            gameTypes.addAll(t.getT2().keySet());
            gameTypes.addAll(t.getT3().keySet());
            gameTypes.retainAll(settings.ratedGameTypes());
            return Flux.fromIterable(gameTypes)
                    .concatMap(g -> {
                        PlayerGameRatingRow r = t.getT1().get(g);
                        PlayerGameStatsRow s = t.getT2().get(g);
                        int tWins = t.getT3().getOrDefault(g, 0L).intValue();
                        return leaderboards.ranksOf(r).map(ranks -> gameRecord(g, r, s, tWins, ranks));
                    })
                    .collectList()
                    .map(list -> {
                        List<GameRecordView> sorted = new ArrayList<>(list);
                        sorted.sort(Comparator.comparing((GameRecordView v) -> v.rating() == null ? Integer.MIN_VALUE : v.rating())
                                .reversed());
                        return sorted;
                    });
        });
    }

    private GameRecordView gameRecord(String gameType, PlayerGameRatingRow r, PlayerGameStatsRow s, int tournamentWins,
                                      CompetitiveDtos.RanksView ranks) {
        int rated = r == null ? 0 : r.ratedGamesPlayed();
        GameStatsView statsView = s == null
                ? new GameStatsView(0, 0, 0, 0, 0.0, 0, 0, 0, tournamentWins, 0)
                : new GameStatsView(s.gamesPlayed(), s.wins(), s.losses(), s.draws(), s.winRate(),
                        s.currentWinStreak(), s.bestWinStreak(), s.top100Wins(), tournamentWins, s.casualGames());
        return new GameRecordView(
                gameType,
                r == null ? null : (int) Math.round(r.rating()),
                r == null ? null : (int) Math.round(r.peakRating()),
                r == null ? null : (int) Math.round(r.ratingDeviation()),
                r == null || r.provisional(),
                Math.min(rated, settings.placementGames()),
                settings.placementGames(),
                ranks,
                statsView,
                r == null ? null : r.lastRatedAt());
    }

    private List<AchievementView> achievementViews(FoundingTier tier, List<PlayerAchievementRow> rows) {
        List<AchievementView> views = new ArrayList<>();
        AchievementType founding = AchievementType.founding(tier);
        if (founding != null) {
            // Derived, never stored — see AchievementType.
            views.add(new AchievementView(founding.name(), founding.label(), founding.icon(), null, null,
                    founding.rarity(), founding.displayPriority(), Map.of()));
        }
        for (PlayerAchievementRow row : rows) {
            AchievementType type = AchievementType.parse(row.type());
            if (type == null) continue;
            views.add(new AchievementView(type.name(), type.label(), type.icon(), row.gameType(), row.earnedAt(),
                    type.rarity(), type.displayPriority(), readMetadata(row)));
        }
        views.sort(Comparator.comparingInt(AchievementView::displayPriority).reversed());
        return views;
    }

    /**
     * City is precise-ish personal location: shown on your own profile, and on
     * anyone else's only if they opted in. Country and region are public — they
     * are what the public rankings are made of.
     */
    private static LocationView location(CompetitiveProfileRow p, boolean own) {
        if (!p.hasCountry()) {
            return own && p.city() != null ? new LocationView(null, null, null, null, p.city(), p.cityPublic()) : null;
        }
        return new LocationView(p.countryCode(), p.countryName(), p.regionCode(), p.regionName(),
                own || p.cityPublic() ? p.city() : null, p.cityPublic());
    }

    private Map<String, Object> readMetadata(PlayerAchievementRow row) {
        if (row.metadata() == null) return Map.of();
        try {
            return mapper.readValue(row.metadata().asString(), new TypeReference<>() {
            });
        } catch (Exception e) {
            return Map.of();
        }
    }

    // ---------------------------------------------------------------- location

    /**
     * Sets where the player competes. Country/region changes go through
     * {@link LocationChangePolicy}; city never does, because it doesn't decide
     * any leaderboard membership.
     */
    public Mono<CompetitiveProfileView> updateLocation(UUID userId, UpdateLocationRequest body) {
        return profiles.findByUserId(userId)
                .defaultIfEmpty(CompetitiveProfileRow.empty(userId))
                .flatMap(current -> {
                    CompetitiveProfileRow next = current;
                    if (body.countryCode() != null) {
                        LocationCatalog.Country country = LocationCatalog.country(body.countryCode())
                                .orElseThrow(() -> ApiExceptions.badRequest("unknown country"));
                        boolean regionGiven = body.regionCode() != null || body.regionName() != null;
                        LocationCatalog.Region region = regionGiven
                                ? LocationCatalog.resolveRegion(country.code(), body.regionCode(), body.regionName())
                                    .orElseThrow(() -> ApiExceptions.badRequest("unknown state / region for " + country.name()))
                                : null;
                        String regionCode = region == null ? null : region.code();
                        Instant now = Instant.now();
                        LocationChangePolicy.Decision decision = locationPolicy.decide(
                                current.countryCode(), current.regionCode(), current.locationChanges(),
                                current.locationLockedUntil(), country.code(), regionCode, now);
                        if (decision instanceof LocationChangePolicy.Rejected rejected) {
                            String when = rejected.retryAt() == null ? "" : " ("
                                    + DateTimeFormatter.ISO_LOCAL_DATE.format(rejected.retryAt().atOffset(ZoneOffset.UTC)) + ")";
                            throw ApiExceptions.conflict(rejected.message() + when);
                        }
                        if (decision instanceof LocationChangePolicy.Allowed allowed) {
                            next = next.withLocation(country.code(), country.name(), regionCode,
                                    region == null ? null : region.name(), allowed.locationChanges(), now,
                                    allowed.lockedUntil());
                        }
                    }
                    if (body.profilePublic() != null && body.profilePublic() != next.profilePublic()) {
                        next = next.withProfilePublic(body.profilePublic());
                    }
                    if (body.city() != null || body.cityPublic() != null) {
                        String city = body.city() == null ? next.city()
                                : (body.city().isBlank() ? null : body.city().trim());
                        boolean cityPublic = body.cityPublic() == null ? next.cityPublic() : body.cityPublic();
                        next = next.withCity(city, cityPublic);
                    }
                    return next == current ? Mono.just(current) : profiles.save(next);
                })
                .then(profileOf(userId, true));
    }

    // ---------------------------------------------------------------- match history

    public Mono<List<MatchHistoryView>> matchesOf(UUID userId, String gameType, int limit) {
        int pageSize = Math.max(1, Math.min(limit, 50));
        String sql = "SELECT m.id, m.game_type, m.ranked, m.unranked_reason, m.draw, m.completed_at, m.duration_ms, "
                + "m.championship_id, p.outcome, p.rating_before, p.rating_after, p.rating_delta, "
                + "(SELECT coalesce(json_agg(json_build_object("
                + "    'userId', o.user_id, 'username', u.username, 'displayName', u.display_name, "
                + "    'isBot', u.is_bot, 'outcome', o.outcome, 'ratingBefore', o.rating_before)), '[]'::json) "
                + "  FROM match_participants o JOIN users u ON u.id = o.user_id "
                + "  WHERE o.match_id = m.id AND o.user_id <> :uid) AS opponents "
                + "FROM match_participants p JOIN match_records m ON m.id = p.match_id "
                + "WHERE p.user_id = :uid " + (gameType == null ? "" : "AND m.game_type = :g ")
                + "ORDER BY m.completed_at DESC LIMIT :limit";
        var spec = db.sql(sql).bind("uid", userId).bind("limit", pageSize);
        if (gameType != null) spec = spec.bind("g", gameType);
        return spec.map(row -> new MatchHistoryView(
                        row.get("id", UUID.class),
                        row.get("game_type", String.class),
                        Boolean.TRUE.equals(row.get("ranked", Boolean.class)),
                        row.get("unranked_reason", String.class),
                        row.get("outcome", String.class),
                        Boolean.TRUE.equals(row.get("draw", Boolean.class)),
                        row.get("completed_at", Instant.class),
                        row.get("duration_ms", Long.class),
                        row.get("championship_id", UUID.class),
                        round(row.get("rating_before", Double.class)),
                        round(row.get("rating_after", Double.class)),
                        round(row.get("rating_delta", Double.class)),
                        opponents(row.get("opponents", Object.class))))
                .all().collectList();
    }

    /**
     * Opponent avatars are deliberately left out: an avatar can be an inline
     * photo, and a page of history shouldn't carry a dozen of them. The app
     * already has avatars for anyone it's shown.
     */
    private List<MatchOpponentView> opponents(Object raw) {
        if (raw == null) return List.of();
        try {
            String json = raw instanceof io.r2dbc.postgresql.codec.Json j ? j.asString() : raw.toString();
            List<Map<String, Object>> list = mapper.readValue(json, new TypeReference<>() {
            });
            return list.stream().map(o -> new MatchOpponentView(
                    UUID.fromString(String.valueOf(o.get("userId"))),
                    (String) o.get("username"),
                    (String) o.get("displayName"),
                    null,
                    Boolean.TRUE.equals(o.get("isBot")),
                    (String) o.get("outcome"),
                    o.get("ratingBefore") instanceof Number n ? (int) Math.round(n.doubleValue()) : null)).toList();
        } catch (Exception e) {
            return List.of();
        }
    }

    private static Integer round(Double value) {
        return value == null ? null : (int) Math.round(value);
    }
}
