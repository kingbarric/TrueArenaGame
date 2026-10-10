package app.truearena.api.slay;

import app.truearena.api.coins.CoinService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.engine.slay.SlayRules;

import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.ReactiveTransactionManager;
import org.springframework.transaction.reactive.TransactionalOperator;

import reactor.core.publisher.Mono;

import java.time.*;
import java.util.*;

@Service
public class SlayCareerService {
    private final DatabaseClient db;
    private final SlayService slay;
    private final SlayCatalog wardrobe;
    private final SlayCareerCatalog career;
    private final CoinService coins;
    private final TransactionalOperator tx;

    public SlayCareerService(
            DatabaseClient db,
            SlayService slay,
            SlayCatalog wardrobe,
            SlayCareerCatalog career,
            CoinService coins,
            ReactiveTransactionManager manager) {
        this.db = db;
        this.slay = slay;
        this.wardrobe = wardrobe;
        this.career = career;
        this.coins = coins;
        tx = TransactionalOperator.create(manager);
    }

    private Mono<List<Map<String, Object>>> bests(UUID user) {
        return db.sql(
                        "SELECT challenge_id,period,best_score,stars,coins_awarded,xp_awarded FROM"
                            + " slay_solo_bests WHERE user_id=:u")
                .bind("u", user)
                .fetch()
                .all()
                .collectList();
    }

    private Map<String, Double> careerBests(List<Map<String, Object>> rows) {
        Map<String, Double> scores = new HashMap<>();
        rows.stream()
                .filter(r -> r.get("period").equals("career"))
                .forEach(
                        r ->
                                scores.put(
                                        (String) r.get("challenge_id"),
                                        ((Number) r.get("best_score")).doubleValue()));
        return scores;
    }

    private Map<String, Object> event(
            SlayCareerCatalog.Challenge c, boolean unlocked, Double best) {
        Map<String, Object> e = new LinkedHashMap<>();
        e.put("id", c.id());
        e.put("title", c.title());
        e.put("brief", c.brief());
        e.put("chapter", c.chapter());
        e.put("chapterTitle", c.chapterTitle());
        e.put("location", c.location());
        e.put("bonus", c.bonus());
        e.put("minimumScore", c.minimumScore());
        e.put("theme", career.theme(c));
        e.put("unlocked", unlocked);
        e.put("personalBest", best);
        e.put("stars", best == null ? 0 : SlayCareerCatalog.stars(best));
        e.put("completed", best != null && best >= c.minimumScore());
        return e;
    }

    private Map<String, Object> state(int xp, List<Map<String, Object>> rows, LocalDate day) {
        var best = careerBests(rows);
        int rank = career.rank(xp, best);
        var events =
                career.content().challenges().stream()
                        .map(c -> event(c, rank >= c.chapter(), best.get(c.id())))
                        .toList();
        var daily = career.challenge("daily", day);
        Double dailyBest =
                rows.stream()
                        .filter(
                                r ->
                                        r.get("period").equals(day.toString())
                                                && r.get("challenge_id").equals(daily.id()))
                        .map(r -> ((Number) r.get("best_score")).doubleValue())
                        .findFirst()
                        .orElse(null);
        Set<String> dates = new HashSet<>();
        rows.stream()
                .filter(r -> !r.get("period").equals("career"))
                .forEach(r -> dates.add((String) r.get("period")));
        LocalDate cursor = dates.contains(day.toString()) ? day : day.minusDays(1);
        int streak = 0;
        while (dates.contains(cursor.toString())) {
            streak++;
            cursor = cursor.minusDays(1);
        }
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("xp", xp);
        s.put("level", 1 + xp / 100);
        s.put("levelXp", xp % 100);
        s.put("rankIndex", rank);
        s.put("rank", career.content().ranks().get(rank));
        s.put(
                "nextRank",
                rank + 1 < career.content().ranks().size()
                        ? career.content().ranks().get(rank + 1)
                        : null);
        s.put(
                "completed",
                events.stream().filter(e -> Boolean.TRUE.equals(e.get("completed"))).count());
        s.put(
                "totalStars",
                events.stream()
                        .filter(e -> Boolean.TRUE.equals(e.get("completed")))
                        .mapToInt(e -> (Integer) e.get("stars"))
                        .sum());
        var dailyEvent = event(daily, true, dailyBest);
        dailyEvent.put("completed", dailyBest != null);
        dailyEvent.put("minimumScore", 0);
        s.put("events", events);
        s.put("daily", dailyEvent);
        s.put("streak", streak);
        s.put("dailyEndsAt", day.plusDays(1).atStartOfDay(ZoneOffset.UTC).toInstant().toString());
        return s;
    }

    public Mono<Map<String, Object>> home(UUID user) {
        return db.sql("SELECT xp FROM slay_profiles WHERE user_id=:u")
                .bind("u", user)
                .map(r -> r.get("xp", Integer.class))
                .one()
                .defaultIfEmpty(0)
                .zipWith(bests(user))
                .map(t -> state(t.getT1(), t.getT2(), LocalDate.now(ZoneOffset.UTC)));
    }

    public Mono<Map<String, Object>> score(UUID user, String eventId, UUID lookId) {
        return score(user, eventId, lookId, LocalDate.now(ZoneOffset.UTC).toString());
    }

    public Mono<Map<String, Object>> score(
            UUID user, String eventId, UUID lookId, String expectedDay) {
        var day = LocalDate.now(ZoneOffset.UTC);
        var challenge = career.challenge(eventId, day);
        if (lookId == null) return Mono.error(ApiExceptions.badRequest("Choose a saved look"));
        if (eventId.equals("daily") && !day.toString().equals(expectedDay))
            return Mono.error(
                    ApiExceptions.badRequest(
                            "Daily Slay has changed. Open the new daily brief before submitting."));
        String period = eventId.equals("daily") ? day.toString() : "career";
        // Lock wallet before profile, matching the existing coin/XP settlement order.
        return tx.transactional(
                db.sql("SELECT id FROM users WHERE id=:u FOR UPDATE")
                        .bind("u", user)
                        .fetch()
                        .one()
                        .then(
                                db.sql(
                                                "INSERT INTO slay_profiles(user_id) VALUES(:u) ON"
                                                    + " CONFLICT DO NOTHING")
                                        .bind("u", user)
                                        .fetch()
                                        .rowsUpdated())
                        .then(
                                db.sql("SELECT xp FROM slay_profiles WHERE user_id=:u FOR UPDATE")
                                        .bind("u", user)
                                        .map(r -> r.get("xp", Integer.class))
                                        .one())
                        .zipWhen(xp -> bests(user))
                        .flatMap(
                                t -> {
                                    int xp = t.getT1();
                                    var rows = t.getT2();
                                    if (period.equals("career")
                                            && career.rank(xp, careerBests(rows))
                                                    < challenge.chapter())
                                        return Mono.error(
                                                ApiExceptions.forbidden(
                                                        "Complete the previous career chapter to"
                                                            + " unlock this event"));
                                    return slay.look(user, lookId)
                                            .flatMap(
                                                    saved -> {
                                                        var judged =
                                                                SlayRules.score(
                                                                        saved.look(),
                                                                        career.theme(challenge),
                                                                        wardrobe.items());
                                                        var old =
                                                                rows.stream()
                                                                        .filter(
                                                                                r ->
                                                                                        r.get(
                                                                                                                "period")
                                                                                                        .equals(
                                                                                                                period)
                                                                                                && r.get(
                                                                                                                "challenge_id")
                                                                                                        .equals(
                                                                                                                challenge
                                                                                                                        .id()))
                                                                        .findFirst()
                                                                        .orElse(Map.of());
                                                        double previous =
                                                                ((Number)
                                                                                old.getOrDefault(
                                                                                        "best_score",
                                                                                        -1d))
                                                                        .doubleValue();
                                                        double best =
                                                                Math.max(
                                                                        previous, judged.overall());
                                                        int stars = SlayCareerCatalog.stars(best);
                                                        boolean passed =
                                                                period.equals("career")
                                                                        ? best
                                                                                >= challenge
                                                                                        .minimumScore()
                                                                        : true;
                                                        int totalCoins =
                                                                passed
                                                                        ? (period.equals("career")
                                                                                        ? 50
                                                                                        : 100)
                                                                                + 25 * stars
                                                                        : 0;
                                                        int totalXp = passed ? 40 + 20 * stars : 0;
                                                        int coinGain =
                                                                totalCoins
                                                                        - ((Number)
                                                                                        old
                                                                                                .getOrDefault(
                                                                                                        "coins_awarded",
                                                                                                        0))
                                                                                .intValue();
                                                        int xpGain =
                                                                totalXp
                                                                        - ((Number)
                                                                                        old
                                                                                                .getOrDefault(
                                                                                                        "xp_awarded",
                                                                                                        0))
                                                                                .intValue();
                                                        return db.sql(
                                                                        "INSERT INTO"
                                                                            + " slay_solo_bests(user_id,challenge_id,period,best_score,stars,coins_awarded,xp_awarded,best_look)"
                                                                            + " VALUES(:u,:c,:p,:s,:n,:coins,:xp,:look)"
                                                                            + " ON CONFLICT(user_id,challenge_id,period)"
                                                                            + " DO UPDATE SET"
                                                                            + " best_look=CASE WHEN"
                                                                            + " EXCLUDED.best_score>slay_solo_bests.best_score"
                                                                            + " THEN"
                                                                            + " EXCLUDED.best_look"
                                                                            + " ELSE"
                                                                            + " slay_solo_bests.best_look"
                                                                            + " END,best_score=EXCLUDED.best_score,stars=EXCLUDED.stars,coins_awarded=EXCLUDED.coins_awarded,xp_awarded=EXCLUDED.xp_awarded,updated_at=now()")
                                                                .bind("u", user)
                                                                .bind("c", challenge.id())
                                                                .bind("p", period)
                                                                .bind("s", best)
                                                                .bind("n", stars)
                                                                .bind("coins", totalCoins)
                                                                .bind("xp", totalXp)
                                                                .bind("look", lookId)
                                                                .fetch()
                                                                .rowsUpdated()
                                                                .then(
                                                                        coinGain > 0
                                                                                ? coins.credit(
                                                                                                user,
                                                                                                coinGain,
                                                                                                "slay_career",
                                                                                                lookId)
                                                                                        .then()
                                                                                : Mono.empty())
                                                                .then(
                                                                        db.sql(
                                                                                        "UPDATE"
                                                                                            + " slay_profiles"
                                                                                            + " SET xp=xp+:x,updated_at=now()"
                                                                                            + " WHERE"
                                                                                            + " user_id=:u")
                                                                                .bind("x", xpGain)
                                                                                .bind("u", user)
                                                                                .fetch()
                                                                                .rowsUpdated())
                                                                .then(bests(user))
                                                                .map(
                                                                        updated -> {
                                                                            Map<String, Object>
                                                                                    result =
                                                                                            new LinkedHashMap<>();
                                                                            result.put(
                                                                                    "themeFit",
                                                                                    judged
                                                                                            .themeFit());
                                                                            result.put(
                                                                                    "requirements",
                                                                                    judged
                                                                                            .requirements());
                                                                            result.put(
                                                                                    "colour",
                                                                                    judged
                                                                                            .colour());
                                                                            result.put(
                                                                                    "completeness",
                                                                                    judged
                                                                                            .completeness());
                                                                            result.put(
                                                                                    "overall",
                                                                                    judged
                                                                                            .overall());
                                                                            result.put(
                                                                                    "stars",
                                                                                    SlayCareerCatalog
                                                                                            .stars(
                                                                                                    judged
                                                                                                            .overall()));
                                                                            result.put(
                                                                                    "starCount", 5);
                                                                            result.put(
                                                                                    "missing",
                                                                                    judged
                                                                                            .missing());
                                                                            result.put(
                                                                                    "feedback",
                                                                                    judged
                                                                                            .feedback());
                                                                            result.put(
                                                                                    "personalBest",
                                                                                    best);
                                                                            result.put(
                                                                                    "newBest",
                                                                                    judged.overall()
                                                                                            > previous);
                                                                            result.put(
                                                                                    "coinsEarned",
                                                                                    coinGain);
                                                                            result.put(
                                                                                    "xpEarned",
                                                                                    xpGain);
                                                                            result.put(
                                                                                    "milestonePassed",
                                                                                    passed);
                                                                            result.put(
                                                                                    "minimumScore",
                                                                                    challenge
                                                                                            .minimumScore());
                                                                            result.put(
                                                                                    "career",
                                                                                    state(
                                                                                            xp
                                                                                                    + xpGain,
                                                                                            updated,
                                                                                            day));
                                                                            return result;
                                                                        });
                                                    });
                                }));
    }
}
