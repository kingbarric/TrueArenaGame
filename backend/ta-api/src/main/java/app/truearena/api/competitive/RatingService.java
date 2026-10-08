package app.truearena.api.competitive;

import app.truearena.api.competitive.RatedMatchPolicy.Seat;
import app.truearena.api.competitive.RatedMatchPolicy.UnrankedReason;
import app.truearena.engine.rating.Glicko2;
import app.truearena.engine.rating.MatchOutcome;
import app.truearena.engine.rating.PairwiseOutcomes;
import app.truearena.engine.rating.RatingSnapshot;
import app.truearena.persistence.PlayerGameRatingRow;
import app.truearena.persistence.UserRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.r2dbc.postgresql.codec.Json;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.ReactiveTransactionManager;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * Turns a finished game into competitive history: a match record, and — when
 * {@link RatedMatchPolicy} says the match counts — new Glicko-2 ratings,
 * per-game stats, and achievements.
 *
 * <p><b>Server-authoritative by construction.</b> The only input is the
 * {@code WinResult} a {@code GameModule} produced inside the orchestrator from
 * moves the engine itself validated. There is no endpoint that accepts a
 * rating, a delta, a rank, or an outcome — nothing for a client to forge.
 *
 * <p><b>Idempotent.</b> {@code match_records.game_session_id} is unique and
 * the insert is {@code ON CONFLICT DO NOTHING}: if a tournament room's
 * {@code finishGame} runs twice, the second call finds the match already
 * recorded and changes nothing.
 *
 * <p><b>Atomic.</b> Everything after the match-row insert runs in one
 * transaction, and each player's rating row is locked ({@code FOR UPDATE}, in
 * user-id order so two concurrent matches can't deadlock) — a player can never
 * end up with a rating that disagrees with the match row that recorded it.
 */
@Service
public class RatingService {

    private static final Logger log = LoggerFactory.getLogger(RatingService.class);

    /** One finished game, as {@code GameOrchestrator.finishGame} sees it. */
    public record FinishedGame(UUID gameSessionId, UUID roomId, String gameType, String winningSide,
                               Map<String, String> perPlayerOutcome, Set<String> connectedAtEnd) {
    }

    private record MatchMeta(Instant startedAt, boolean roomRanked, UUID championshipId) {
    }

    private record Rated(PlayerGameRatingRow before, RatingSnapshot after, String outcome) {
    }

    private final DatabaseClient db;
    private final UserRepository users;
    private final LeaderboardService leaderboards;
    private final CompetitiveSettings settings;
    private final RatedMatchPolicy policy;
    private final ObjectMapper mapper;
    private final TransactionalOperator tx;

    public RatingService(DatabaseClient db, UserRepository users, LeaderboardService leaderboards,
                         CompetitiveSettings settings, ObjectMapper mapper,
                         ObjectProvider<ReactiveTransactionManager> transactions) {
        this.db = db;
        this.users = users;
        this.leaderboards = leaderboards;
        this.settings = settings;
        this.policy = new RatedMatchPolicy(settings);
        this.mapper = mapper;
        ReactiveTransactionManager manager = transactions.getIfAvailable();
        this.tx = manager == null ? null : TransactionalOperator.create(manager);
    }

    /**
     * Records the match and applies any rating change. Callers treat this as
     * best-effort — a failure here must never cost anyone their coins, stake
     * payout or bracket advancement — but the work itself is all-or-nothing.
     */
    public Mono<Void> recordMatch(FinishedGame game) {
        Map<String, String> outcome = new LinkedHashMap<>();
        game.perPlayerOutcome().forEach((id, result) -> {
            if (parseUuid(id) != null) outcome.put(id, result);
        });
        if (outcome.isEmpty()) {
            return Mono.empty();
        }
        return Mono.zip(meta(game.gameSessionId()), seats(outcome.keySet()), forfeiters(game.gameSessionId()))
                .flatMap(t -> {
                    MatchMeta meta = t.getT1();
                    List<Seat> seats = t.getT2();
                    Set<String> forfeited = t.getT3();
                    boolean championship = meta.championshipId() != null && (!"slayhuud".equals(game.gameType()) || meta.roomRanked());
                    Optional<UnrankedReason> early = policy.decide(game.gameType(), meta.roomRanked(), championship, seats, 0);
                    Mono<Optional<UnrankedReason>> decision = early.isPresent()
                            ? Mono.just(early)
                            : maxPairGamesToday(game.gameType(), seats).map(n ->
                                    policy.decide(game.gameType(), meta.roomRanked(), championship, seats, n));
                    return decision.flatMap(reason -> transactional(
                            persist(game, outcome, meta, seats, forfeited, reason.orElse(null)))
                            .flatMap(rated -> rated ? leaderboards.invalidate(game.gameType()) : Mono.empty()));
                })
                .then();
    }

    // ---------------------------------------------------------------- the write

    /** @return whether ratings moved (so the caller knows to invalidate cached boards). */
    private Mono<Boolean> persist(FinishedGame game, Map<String, String> outcome, MatchMeta meta, List<Seat> seats,
                                  Set<String> forfeited, UnrankedReason reason) {
        boolean draw = !outcome.isEmpty() && outcome.values().stream().allMatch(PairwiseOutcomes.TIED::equals);
        Instant now = Instant.now();
        Long durationMs = meta.startedAt() == null ? null : Duration.between(meta.startedAt(), now).toMillis();

        var insert = db.sql("INSERT INTO match_records (game_session_id, room_id, championship_id, game_type, ranked, "
                        + "unranked_reason, winning_side, draw, player_count, started_at, completed_at, duration_ms) "
                        + "VALUES (:session, :room, :championship, :g, :ranked, :reason, :side, :draw, :count, :started, :now, :duration) "
                        + "ON CONFLICT (game_session_id) DO NOTHING RETURNING id")
                .bind("session", game.gameSessionId())
                .bind("g", game.gameType())
                .bind("ranked", reason == null)
                .bind("draw", draw)
                .bind("count", seats.size())
                .bind("now", now);
        insert = bindNullable(insert, "room", game.roomId(), UUID.class);
        insert = bindNullable(insert, "championship", meta.championshipId(), UUID.class);
        insert = bindNullable(insert, "reason", reason == null ? null : reason.code(), String.class);
        insert = bindNullable(insert, "side", game.winningSide(), String.class);
        insert = bindNullable(insert, "started", meta.startedAt(), Instant.class);
        insert = bindNullable(insert, "duration", durationMs, Long.class);

        return insert.map(row -> row.get("id", UUID.class)).one()
                // Empty = this session is already recorded: an idempotent replay, nothing to do.
                .flatMap(matchId -> reason == null
                        ? rate(matchId, game, outcome, seats, forfeited).thenReturn(true)
                        : recordUnrated(matchId, game, outcome, seats, forfeited, reason).thenReturn(false))
                .defaultIfEmpty(false);
    }

    /**
     * An unrated match still keeps its participants (bots included — "who did
     * you play" is part of the history), with no rating columns. A casual game
     * between people bumps {@code casual_games}; nothing else moves.
     */
    private Mono<Void> recordUnrated(UUID matchId, FinishedGame game, Map<String, String> outcome, List<Seat> seats,
                                     Set<String> forfeited, UnrankedReason reason) {
        boolean humansOnly = seats.stream().noneMatch(Seat::bot) && seats.size() >= 2;
        return Flux.fromIterable(seats)
                .concatMap(seat -> insertParticipant(matchId, seat.userId(), outcome.get(seat.userId()),
                        forfeited.contains(seat.userId()), !game.connectedAtEnd().contains(seat.userId()),
                        null, null, null)
                        .then(humansOnly && !seat.guest() && settings.isRated(game.gameType())
                                ? db.sql("INSERT INTO player_game_stats (user_id, game_type, casual_games, last_played_at) "
                                        + "VALUES (:uid, :g, 1, now()) ON CONFLICT (user_id, game_type) DO UPDATE "
                                        + "SET casual_games = player_game_stats.casual_games + 1, "
                                        + "last_played_at = now(), updated_at = now()")
                                .bind("uid", UUID.fromString(seat.userId())).bind("g", game.gameType())
                                .fetch().rowsUpdated().then()
                                : Mono.empty()))
                .then()
                .doOnSuccess(v -> log.debug("match {} recorded unranked ({})", matchId, reason.code()));
    }

    private Mono<Void> rate(UUID matchId, FinishedGame game, Map<String, String> outcome, List<Seat> seats,
                            Set<String> forfeited) {
        List<UUID> ids = seats.stream().map(s -> UUID.fromString(s.userId())).sorted().toList();
        return Flux.fromIterable(ids)
                .concatMap(id -> ensureRating(id, game.gameType()).then(lockRating(id, game.gameType())))
                .collectList()
                .flatMap(rows -> Flux.fromIterable(rows)
                        .concatMap(row -> leaderboards.globalRankOf(row)
                                .map(rank -> Map.entry(row.userId().toString(), rank)))
                        .collectMap(Map.Entry::getKey, Map.Entry::getValue)
                        .flatMap(preRanks -> applyRatings(matchId, game, outcome, rows, preRanks, forfeited)))
                .then(db.sql("UPDATE match_records SET rated_at = now() WHERE id = :id").bind("id", matchId)
                        .fetch().rowsUpdated().then());
    }

    private Mono<Void> applyRatings(UUID matchId, FinishedGame game, Map<String, String> outcome,
                                    List<PlayerGameRatingRow> rows, Map<String, Integer> preRanks,
                                    Set<String> forfeited) {
        Map<String, RatingSnapshot> before = new HashMap<>();
        Map<String, PlayerGameRatingRow> byId = new HashMap<>();
        for (PlayerGameRatingRow row : rows) {
            String id = row.userId().toString();
            before.put(id, new RatingSnapshot(row.rating(), row.ratingDeviation(), row.volatility()));
            byId.put(id, row);
        }
        // Every new rating is computed from everyone's PRE-match state before any
        // is written — otherwise the second player would be rated against the
        // first player's already-updated rating.
        Map<String, List<MatchOutcome>> pairwise = PairwiseOutcomes.expand(outcome, before);
        List<Rated> results = new ArrayList<>();
        pairwise.forEach((id, against) ->
                results.add(new Rated(byId.get(id), Glicko2.update(before.get(id), against), outcome.get(id))));

        return Flux.fromIterable(results).concatMap(r -> {
            String id = r.before().userId().toString();
            double opponentMean = before.entrySet().stream()
                    .filter(e -> !e.getKey().equals(id))
                    .mapToDouble(e -> e.getValue().rating()).average().orElse(Double.NaN);
            Integer bestBeatenRank = outcome.keySet().stream()
                    .filter(other -> !other.equals(id))
                    .filter(other -> PairwiseOutcomes.score(r.outcome(), outcome.get(other)) == MatchOutcome.WIN)
                    .map(preRanks::get)
                    .filter(java.util.Objects::nonNull)
                    .min(Integer::compare)
                    .orElse(null);
            return updateRating(r)
                    .then(insertParticipant(matchId, id, r.outcome(), forfeited.contains(id),
                            !game.connectedAtEnd().contains(id), r.before(), r.after(),
                            Double.isNaN(opponentMean) ? null : opponentMean))
                    .then(updateStats(r, game.gameType(), bestBeatenRank))
                    .flatMap(stats -> awardAchievements(r.before().userId(), game.gameType(), matchId,
                            (PairwiseOutcomes.WON.equals(r.outcome()) || "rank:1".equals(r.outcome())), stats[0], stats[1], bestBeatenRank,
                            bestBeatenOpponent(id, r.outcome(), outcome, preRanks, bestBeatenRank)));
        }).then();
    }

    private Mono<Void> updateRating(Rated r) {
        int rated = r.before().ratedGamesPlayed() + 1;
        boolean provisional = rated < settings.placementGames();
        return db.sql("UPDATE player_game_ratings SET rating = :rating, rating_deviation = :rd, volatility = :vol, "
                        + "peak_rating = GREATEST(peak_rating, :rating), rated_games_played = :n, "
                        + "provisional = :provisional, leaderboard_eligible = :eligible, last_rated_at = now() "
                        + "WHERE id = :id")
                .bind("rating", r.after().rating())
                .bind("rd", r.after().deviation())
                .bind("vol", r.after().volatility())
                .bind("n", rated)
                .bind("provisional", provisional)
                // Eligibility beyond placement (guest, bot) is already enforced by
                // RatedMatchPolicy: only a verified human ever reaches this line.
                .bind("eligible", !provisional)
                .bind("id", r.before().id())
                .fetch().rowsUpdated().then();
    }

    /** @return {@code [rankedWins, currentWinStreak]} after this match, for achievements. */
    private Mono<int[]> updateStats(Rated r, String gameType, Integer bestBeatenRank) {
        int win = (PairwiseOutcomes.WON.equals(r.outcome()) || "rank:1".equals(r.outcome())) ? 1 : 0;
        int draw = PairwiseOutcomes.TIED.equals(r.outcome()) ? 1 : 0;
        int loss = 1 - win - draw;
        int top100 = win == 1 && bestBeatenRank != null && bestBeatenRank <= 100 ? 1 : 0;
        return db.sql("INSERT INTO player_game_stats (user_id, game_type, games_played, wins, losses, draws, "
                        + "current_win_streak, best_win_streak, top100_wins, last_played_at) "
                        + "VALUES (:uid, :g, 1, :w, :l, :d, :w, :w, :t, now()) "
                        + "ON CONFLICT (user_id, game_type) DO UPDATE SET "
                        + "games_played = player_game_stats.games_played + 1, "
                        + "wins = player_game_stats.wins + :w, "
                        + "losses = player_game_stats.losses + :l, "
                        + "draws = player_game_stats.draws + :d, "
                        // A draw ends a WIN streak just as a loss does.
                        + "current_win_streak = CASE WHEN :w = 1 THEN player_game_stats.current_win_streak + 1 ELSE 0 END, "
                        + "best_win_streak = GREATEST(player_game_stats.best_win_streak, "
                        + "    CASE WHEN :w = 1 THEN player_game_stats.current_win_streak + 1 ELSE 0 END), "
                        + "top100_wins = player_game_stats.top100_wins + :t, "
                        + "last_played_at = now(), updated_at = now() "
                        + "RETURNING wins, current_win_streak")
                .bind("uid", r.before().userId()).bind("g", gameType)
                .bind("w", win).bind("l", loss).bind("d", draw).bind("t", top100)
                .map(row -> new int[]{row.get("wins", Integer.class), row.get("current_win_streak", Integer.class)})
                .one();
    }

    private Mono<Void> awardAchievements(UUID userId, String gameType, UUID matchId, boolean won, int rankedWins,
                                         int streak, Integer bestBeatenRank, String beatenOpponent) {
        Set<AchievementType> earned = AchievementRules.earned(won, rankedWins, streak, bestBeatenRank);
        return Flux.fromIterable(earned).concatMap(type -> {
            Map<String, Object> metadata = new LinkedHashMap<>();
            metadata.put("matchId", matchId.toString());
            if (type == AchievementType.DEFEATED_TOP_100 || type == AchievementType.DEFEATED_TOP_10
                    || type == AchievementType.DEFEATED_NO_1) {
                metadata.put("opponentRank", bestBeatenRank);
                if (beatenOpponent != null) metadata.put("opponentId", beatenOpponent);
            }
            // ON CONFLICT DO NOTHING: the first time you earn a badge is the one
            // that's kept — its earned_at and metadata are history.
            return db.sql("INSERT INTO player_achievements (user_id, type, game_type, metadata, display_priority, rarity) "
                            + "VALUES (:uid, :type, :g, :meta, :priority, :rarity) "
                            + "ON CONFLICT (user_id, type, game_type) DO NOTHING")
                    .bind("uid", userId).bind("type", type.name()).bind("g", gameType)
                    .bind("meta", Json.of(writeJson(metadata)))
                    .bind("priority", type.displayPriority()).bind("rarity", type.rarity())
                    .fetch().rowsUpdated().then();
        }).then();
    }

    private static String bestBeatenOpponent(String id, String mine, Map<String, String> outcome,
                                             Map<String, Integer> preRanks, Integer bestRank) {
        if (bestRank == null) return null;
        return outcome.keySet().stream()
                .filter(other -> !other.equals(id))
                .filter(other -> PairwiseOutcomes.score(mine, outcome.get(other)) == MatchOutcome.WIN)
                .filter(other -> bestRank.equals(preRanks.get(other)))
                .findFirst().orElse(null);
    }

    private Mono<Void> insertParticipant(UUID matchId, String userId, String outcome, boolean forfeited,
                                         boolean disconnected, PlayerGameRatingRow before, RatingSnapshot after,
                                         Double opponentMean) {
        String normalised = "rank:1".equals(outcome) ? PairwiseOutcomes.WON : PairwiseOutcomes.WON.equals(outcome) || PairwiseOutcomes.TIED.equals(outcome) ? outcome : PairwiseOutcomes.LOST;
        var spec = db.sql("INSERT INTO match_participants (match_id, user_id, outcome, forfeited, disconnected, "
                        + "rating_before, rating_after, rating_delta, deviation_before, deviation_after, opponent_rating_before) "
                        + "VALUES (:match, :uid, :outcome, :forfeited, :disconnected, :rb, :ra, :delta, :db, :da, :opp) "
                        + "ON CONFLICT (match_id, user_id) DO NOTHING")
                .bind("match", matchId).bind("uid", UUID.fromString(userId)).bind("outcome", normalised)
                .bind("forfeited", forfeited).bind("disconnected", disconnected);
        spec = bindNullable(spec, "rb", before == null ? null : before.rating(), Double.class);
        spec = bindNullable(spec, "ra", after == null ? null : after.rating(), Double.class);
        spec = bindNullable(spec, "delta", before == null || after == null ? null : after.rating() - before.rating(), Double.class);
        spec = bindNullable(spec, "db", before == null ? null : before.ratingDeviation(), Double.class);
        spec = bindNullable(spec, "da", after == null ? null : after.deviation(), Double.class);
        spec = bindNullable(spec, "opp", opponentMean, Double.class);
        return spec.fetch().rowsUpdated().then(outcome != null && outcome.startsWith("rank:")
                ? db.sql("UPDATE match_participants SET placement=:p WHERE match_id=:m AND user_id=:u")
                  .bind("p", Integer.parseInt(outcome.substring(5))).bind("m", matchId).bind("u", UUID.fromString(userId)).fetch().rowsUpdated().then()
                : Mono.empty());
    }

    /**
     * Created lazily on a player's first rated game in this game type — never
     * pre-seeded, or every account would sit on every board at 1500. The new
     * row copies the player's current location; after that the
     * competitive_profiles trigger keeps it in step.
     */
    private Mono<Void> ensureRating(UUID userId, String gameType) {
        return db.sql("INSERT INTO player_game_ratings (user_id, game_type, country_code, region_code) "
                        + "SELECT :uid, :g, p.country_code, p.region_code "
                        + "FROM (SELECT 1) AS one LEFT JOIN competitive_profiles p ON p.user_id = :uid "
                        + "ON CONFLICT (user_id, game_type) DO NOTHING")
                .bind("uid", userId).bind("g", gameType)
                .fetch().rowsUpdated().then();
    }

    private Mono<PlayerGameRatingRow> lockRating(UUID userId, String gameType) {
        return db.sql("SELECT * FROM player_game_ratings WHERE user_id = :uid AND game_type = :g FOR UPDATE")
                .bind("uid", userId).bind("g", gameType)
                .map(row -> new PlayerGameRatingRow(
                        row.get("id", UUID.class),
                        row.get("user_id", UUID.class),
                        row.get("game_type", String.class),
                        row.get("rating", Double.class),
                        row.get("rating_deviation", Double.class),
                        row.get("volatility", Double.class),
                        row.get("peak_rating", Double.class),
                        row.get("rated_games_played", Integer.class),
                        Boolean.TRUE.equals(row.get("provisional", Boolean.class)),
                        Boolean.TRUE.equals(row.get("leaderboard_eligible", Boolean.class)),
                        row.get("country_code", String.class),
                        row.get("region_code", String.class),
                        row.get("last_rated_at", Instant.class),
                        row.get("created_at", Instant.class)))
                .one();
    }

    // ---------------------------------------------------------------- inputs to the policy

    /**
     * Started-at, the host's ranked request, and the championship (if any).
     * The championship link goes through {@code championship_games} rather than
     * {@code championship_matches.room_id}, because a drawn bracket game clears
     * the match's room before this runs.
     */
    private Mono<MatchMeta> meta(UUID sessionId) {
        return db.sql("SELECT s.started_at, coalesce(r.ranked, false) AS ranked, cm.championship_id "
                        + "FROM game_sessions s LEFT JOIN rooms r ON r.id = s.room_id "
                        + "LEFT JOIN championship_games cg ON cg.game_session_id = s.id "
                        + "LEFT JOIN championship_matches cm ON cm.id = cg.match_id "
                        + "WHERE s.id = :sid")
                .bind("sid", sessionId)
                .map(row -> new MatchMeta(row.get("started_at", Instant.class),
                        Boolean.TRUE.equals(row.get("ranked", Boolean.class)),
                        row.get("championship_id", UUID.class)))
                .one()
                .defaultIfEmpty(new MatchMeta(null, false, null));
    }

    private Mono<List<Seat>> seats(Set<String> ids) {
        return Flux.fromIterable(ids)
                .concatMap(id -> users.findById(UUID.fromString(id))
                        .map(u -> new Seat(id, u.isBot(), u.isGuest())))
                .collectList();
    }

    /** Tournament forfeits are durably logged; that's the only forfeit source that survives a restart. */
    private Mono<Set<String>> forfeiters(UUID sessionId) {
        return db.sql("SELECT actor_id FROM championship_actions WHERE game_session_id = :sid AND action_type = 'FORFEIT'")
                .bind("sid", sessionId)
                .map(row -> String.valueOf(row.get("actor_id", UUID.class)))
                .all()
                .collect(java.util.stream.Collectors.toSet());
    }

    /** The busiest pair among these players: rated games against each other in the last 24h. */
    private Mono<Integer> maxPairGamesToday(String gameType, List<Seat> seats) {
        List<UUID> ids = seats.stream().map(s -> UUID.fromString(s.userId())).toList();
        List<UUID[]> pairs = new ArrayList<>();
        for (int i = 0; i < ids.size(); i++) {
            for (int j = i + 1; j < ids.size(); j++) {
                pairs.add(new UUID[]{ids.get(i), ids.get(j)});
            }
        }
        return Flux.fromIterable(pairs)
                .concatMap(pair -> db.sql("SELECT count(*) AS n FROM match_records m "
                                + "JOIN match_participants a ON a.match_id = m.id AND a.user_id = :a "
                                + "JOIN match_participants b ON b.match_id = m.id AND b.user_id = :b "
                                + "WHERE m.ranked AND m.game_type = :g AND m.completed_at > now() - interval '24 hours'")
                        .bind("a", pair[0]).bind("b", pair[1]).bind("g", gameType)
                        .map(row -> row.get("n", Long.class)).one().defaultIfEmpty(0L))
                .reduce(0L, Math::max)
                .map(Long::intValue);
    }

    // ---------------------------------------------------------------- plumbing

    private <T> Mono<T> transactional(Mono<T> work) {
        return tx == null ? work : tx.transactional(work);
    }

    private static <T> DatabaseClient.GenericExecuteSpec bindNullable(DatabaseClient.GenericExecuteSpec spec,
                                                                      String name, T value, Class<T> type) {
        return value == null ? spec.bindNull(name, type) : spec.bind(name, value);
    }

    private String writeJson(Object value) {
        try {
            return mapper.writeValueAsString(value);
        } catch (Exception e) {
            return "{}";
        }
    }

    private static UUID parseUuid(String raw) {
        try {
            return raw == null ? null : UUID.fromString(raw);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }
}
