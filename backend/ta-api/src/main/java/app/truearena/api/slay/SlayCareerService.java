package app.truearena.api.slay;

import app.truearena.api.coins.CoinService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.engine.slay.SlayRules;
import app.truearena.persistence.FriendRow;

import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.ReactiveTransactionManager;
import org.springframework.transaction.reactive.TransactionalOperator;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.*;
import java.util.*;

/**
 * Solo career: one character for the whole journey, stage-by-stage wardrobes,
 * personal bests, rewards and leaderboards. PvP ratings stay separate.
 */
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

    /** The career character, chosen once: avatar body plus a character of that body. */
    record Character(String body, String avatarId) {}

    /** Everything a career decision needs, read together. */
    private record Player(
            int xp,
            List<Map<String, Object>> bests,
            Optional<Character> character,
            Set<String> granted) {
        int rank(SlayCareerCatalog career) {
            return career.rank(xp, careerBests(bests));
        }
    }

    private Mono<Player> player(UUID user, boolean lock) {
        Mono<Object[]> profile =
                db.sql(
                                "SELECT xp,career_body,career_avatar FROM slay_profiles WHERE"
                                        + " user_id=:u"
                                        + (lock ? " FOR UPDATE" : ""))
                        .bind("u", user)
                        .map(
                                r ->
                                        new Object[] {
                                            r.get("xp", Integer.class),
                                            r.get("career_body", String.class),
                                            r.get("career_avatar", String.class)
                                        })
                        .one()
                        .defaultIfEmpty(new Object[] {0, null, null});
        // Wardrobe rows only: catalogue defaults are not career rewards.
        Mono<Set<String>> granted =
                db.sql("SELECT item_id FROM slay_wardrobe WHERE user_id=:u")
                        .bind("u", user)
                        .map(r -> r.get("item_id", String.class))
                        .all()
                        .collect(java.util.stream.Collectors.toSet());
        return Mono.zip(profile, bests(user), granted)
                .map(
                        t -> {
                            Object[] p = t.getT1();
                            Optional<Character> character =
                                    p[1] == null
                                            ? Optional.empty()
                                            : Optional.of(
                                                    new Character((String) p[1], (String) p[2]));
                            return new Player(
                                    (Integer) p[0],
                                    t.getT2(),
                                    character,
                                    new HashSet<>(t.getT3()));
                        });
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

    private static Map<String, Double> careerBests(List<Map<String, Object>> rows) {
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

    /** Opens every stage collection up to {@code rank} in the wardrobe; idempotent. */
    private Mono<List<String>> grantStages(UUID user, String body, int rank, Set<String> granted) {
        List<String> missing =
                career.stageItems(body, rank).stream().filter(id -> !granted.contains(id)).toList();
        return Flux.fromIterable(missing)
                .concatMap(id -> grant(user, id, "career"))
                .then(Mono.fromCallable(() -> {
                    granted.addAll(missing);
                    return missing;
                }));
    }

    private Mono<Long> grant(UUID user, String item, String source) {
        return db.sql(
                        "INSERT INTO slay_wardrobe(user_id,item_id,source) VALUES(:u,:i,:s) ON"
                                + " CONFLICT DO NOTHING")
                .bind("u", user)
                .bind("i", item)
                .bind("s", source)
                .fetch()
                .rowsUpdated();
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

    private Map<String, Object> state(Player p, LocalDate day) {
        var best = careerBests(p.bests());
        int rank = career.rank(p.xp(), best);
        var events =
                career.content().challenges().stream()
                        .map(c -> event(c, rank >= c.chapter(), best.get(c.id())))
                        .toList();
        var daily = career.challenge("daily", day);
        Double dailyBest =
                p.bests().stream()
                        .filter(
                                r ->
                                        r.get("period").equals(day.toString())
                                                && r.get("challenge_id").equals(daily.id()))
                        .map(r -> ((Number) r.get("best_score")).doubleValue())
                        .findFirst()
                        .orElse(null);
        Set<String> dates = new HashSet<>();
        p.bests().stream()
                .filter(r -> !r.get("period").equals("career"))
                .forEach(r -> dates.add((String) r.get("period")));
        LocalDate cursor = dates.contains(day.toString()) ? day : day.minusDays(1);
        int streak = 0;
        while (dates.contains(cursor.toString())) {
            streak++;
            cursor = cursor.minusDays(1);
        }
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("xp", p.xp());
        s.put("level", 1 + p.xp() / 100);
        s.put("levelXp", p.xp() % 100);
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
        s.put(
                "chapters",
                career.content().chapters().stream()
                        .map(
                                c -> {
                                    Map<String, Object> m = new LinkedHashMap<>();
                                    m.put("chapter", c.chapter());
                                    m.put("title", c.title());
                                    m.put("location", c.location());
                                    m.put("room", c.room());
                                    m.put("venue", c.venue());
                                    m.put("unlocked", rank >= c.chapter());
                                    return m;
                                })
                        .toList());
        Map<String, Object> character = null;
        if (p.character().isPresent()) {
            var ch = p.character().get();
            character = new LinkedHashMap<>();
            character.put("body", ch.body());
            character.put("avatarId", ch.avatarId());
            character.put("items", career.careerItems(ch.body(), rank, p.granted()));
            character.put("poses", career.poses(rank));
        }
        s.put("character", character);
        return s;
    }

    public Mono<Map<String, Object>> home(UUID user) {
        // Reading home also repairs any stage collection a past rank opened.
        return tx.transactional(
                player(user, false)
                        .flatMap(
                                p ->
                                        p.character().isEmpty()
                                                ? Mono.just(p)
                                                : grantStages(
                                                                user,
                                                                p.character().get().body(),
                                                                p.rank(career),
                                                                p.granted())
                                                        .thenReturn(p))
                        .map(p -> state(p, LocalDate.now(ZoneOffset.UTC))));
    }

    /** Chooses the career character. It stays for the whole career. */
    public Mono<Map<String, Object>> start(UUID user, String body, String avatarId) {
        String character = avatarId == null || avatarId.isBlank() ? body : avatarId;
        try {
            wardrobe.validateAvatar(
                    new SlayRules.Look(
                            body, "", "", Map.of(), "", "", Map.of(), character));
        } catch (IllegalArgumentException e) {
            return Mono.error(ApiExceptions.badRequest(e.getMessage()));
        }
        return tx.transactional(
                        db.sql("INSERT INTO slay_profiles(user_id) VALUES(:u) ON CONFLICT DO NOTHING")
                                .bind("u", user)
                                .fetch()
                                .rowsUpdated()
                                .then(
                                        db.sql(
                                                        "UPDATE slay_profiles SET career_body=:b,"
                                                                + "career_avatar=:a,updated_at=now()"
                                                                + " WHERE user_id=:u AND"
                                                                + " career_body IS NULL")
                                                .bind("b", body)
                                                .bind("a", character)
                                                .bind("u", user)
                                                .fetch()
                                                .rowsUpdated())
                                .flatMap(
                                        n ->
                                                n == 0
                                                        ? Mono.error(
                                                                ApiExceptions.conflict(
                                                                        "Your career character is"
                                                                                + " already chosen"))
                                                        : player(user, false))
                                .flatMap(
                                        p ->
                                                grantStages(user, body, p.rank(career), p.granted())))
                .then(home(user));
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
                        .then(player(user, true))
                        .zipWhen(p -> slay.look(user, lookId))
                        .flatMap(t -> settle(user, challenge, period, day, lookId, t.getT1(), t.getT2())));
    }

    private Mono<Map<String, Object>> settle(
            UUID user,
            SlayCareerCatalog.Challenge challenge,
            String period,
            LocalDate day,
            UUID lookId,
            Player p,
            SlayService.SavedLook saved) {
        int rank = p.rank(career);
        if (period.equals("career") && rank < challenge.chapter())
            return Mono.error(
                    ApiExceptions.forbidden(
                            "Complete the previous career chapter to unlock this event"));
        if (p.character().isEmpty())
            return Mono.error(ApiExceptions.conflict("Choose your career character first"));
        var character = p.character().get();
        var look = saved.look();
        String lookCharacter = look.avatarId() == null ? look.body() : look.avatarId();
        if (!look.body().equals(character.body()) || !lookCharacter.equals(character.avatarId()))
            return Mono.error(
                    ApiExceptions.badRequest("Your career is styled on your chosen character"));
        var available = career.careerItems(character.body(), rank, p.granted());
        var items = wardrobe.items();
        for (String id : look.items().values()) {
            var item = items.get(id);
            if (item != null
                    && !SlayCareerCatalog.BEAUTY.contains(item.category())
                    && !available.contains(id))
                return Mono.error(
                        ApiExceptions.badRequest(item.name() + " unlocks later in your career"));
        }
        if (!career.poses(rank).contains(look.pose()))
            return Mono.error(ApiExceptions.badRequest("That pose unlocks later in your career"));

        var judged = SlayRules.score(look, career.theme(challenge), items);
        var old =
                p.bests().stream()
                        .filter(
                                r ->
                                        r.get("period").equals(period)
                                                && r.get("challenge_id").equals(challenge.id()))
                        .findFirst()
                        .orElse(Map.of());
        double previous = ((Number) old.getOrDefault("best_score", -1d)).doubleValue();
        int previousStars = ((Number) old.getOrDefault("stars", 0)).intValue();
        double best = Math.max(previous, judged.overall());
        int stars = SlayCareerCatalog.stars(best);
        boolean passed = !period.equals("career") || best >= challenge.minimumScore();
        int totalCoins = passed ? (period.equals("career") ? 50 : 100) + 25 * stars : 0;
        int totalXp = passed ? 40 + 20 * stars : 0;
        int coinGain = totalCoins - ((Number) old.getOrDefault("coins_awarded", 0)).intValue();
        int xpGain = totalXp - ((Number) old.getOrDefault("xp_awarded", 0)).intValue();
        // A first 4★ and a first 5★ on a career event each unlock a piece from its stage pool.
        List<String> rewards = new ArrayList<>();
        if (period.equals("career"))
            for (int tier : List.of(4, 5))
                if (previousStars < tier && stars >= tier)
                    career.nextReward(character.body(), challenge.chapter(), tier, p.granted())
                            .ifPresent(
                                    id -> {
                                        rewards.add(id);
                                        p.granted().add(id);
                                    });
        return db.sql(
                        "INSERT INTO"
                            + " slay_solo_bests(user_id,challenge_id,period,best_score,stars,coins_awarded,xp_awarded,best_look)"
                            + " VALUES(:u,:c,:p,:s,:n,:coins,:xp,:look) ON"
                            + " CONFLICT(user_id,challenge_id,period) DO UPDATE SET"
                            + " best_look=CASE WHEN EXCLUDED.best_score>slay_solo_bests.best_score"
                            + " THEN EXCLUDED.best_look ELSE slay_solo_bests.best_look"
                            + " END,best_score=EXCLUDED.best_score,stars=EXCLUDED.stars,"
                            + "coins_awarded=EXCLUDED.coins_awarded,xp_awarded=EXCLUDED.xp_awarded,"
                            + "updated_at=now()")
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
                                ? coins.credit(user, coinGain, "slay_career", lookId).then()
                                : Mono.empty())
                .then(
                        db.sql(
                                        "UPDATE slay_profiles SET xp=xp+:x,updated_at=now() WHERE"
                                                + " user_id=:u")
                                .bind("x", xpGain)
                                .bind("u", user)
                                .fetch()
                                .rowsUpdated())
                .thenMany(Flux.fromIterable(rewards).concatMap(id -> grant(user, id, "career_reward")))
                .then(bests(user))
                .flatMap(
                        updated -> {
                            var after =
                                    new Player(p.xp() + xpGain, updated, p.character(), p.granted());
                            int newRank = after.rank(career);
                            Mono<List<String>> opened =
                                    newRank > rank
                                            ? grantStages(
                                                    user, character.body(), newRank, p.granted())
                                            : Mono.just(List.of());
                            return opened.zipWith(board(user, challenge, period))
                                    .map(
                                            t -> {
                                                Map<String, Object> result = new LinkedHashMap<>();
                                                result.put("themeFit", judged.themeFit());
                                                result.put("requirements", judged.requirements());
                                                result.put("colour", judged.colour());
                                                result.put("completeness", judged.completeness());
                                                result.put("overall", judged.overall());
                                                result.put(
                                                        "stars",
                                                        SlayCareerCatalog.stars(judged.overall()));
                                                result.put("starCount", 5);
                                                result.put("missing", judged.missing());
                                                result.put("feedback", judged.feedback());
                                                result.put("personalBest", best);
                                                result.put("newBest", judged.overall() > previous);
                                                result.put("coinsEarned", coinGain);
                                                result.put("xpEarned", xpGain);
                                                result.put("milestonePassed", passed);
                                                result.put(
                                                        "minimumScore", challenge.minimumScore());
                                                result.put("unlocked", describe(rewards));
                                                result.put(
                                                        "rankUp",
                                                        newRank > rank
                                                                ? rankUp(newRank, t.getT1())
                                                                : null);
                                                result.put("ranking", t.getT2());
                                                result.put("career", state(after, day));
                                                return result;
                                            });
                        });
    }

    private List<Map<String, Object>> describe(List<String> ids) {
        var items = wardrobe.items();
        return ids.stream()
                .map(items::get)
                .filter(Objects::nonNull)
                .map(
                        i -> {
                            Map<String, Object> m = new LinkedHashMap<>();
                            m.put("id", i.id());
                            m.put("name", i.name());
                            m.put("category", i.category());
                            m.put("thumbnailUrl", i.thumbnailUrl());
                            return m;
                        })
                .toList();
    }

    private Map<String, Object> rankUp(int rank, List<String> opened) {
        var chapter = career.chapter(Math.min(rank, career.content().chapters().size() - 1));
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("rank", career.content().ranks().get(rank).name());
        m.put("chapter", chapter.title());
        m.put("location", chapter.location());
        m.put("room", chapter.room());
        m.put("venue", chapter.venue());
        m.put("poses", chapter.poses());
        m.put("items", describe(opened));
        return m;
    }

    /** Daily and career-event standings: global position and the player's friends. */
    public Mono<Map<String, Object>> leaderboard(UUID user, String eventId) {
        var day = LocalDate.now(ZoneOffset.UTC);
        var challenge = career.challenge(eventId, day);
        return board(user, challenge, eventId.equals("daily") ? day.toString() : "career");
    }

    private Mono<Map<String, Object>> board(
            UUID user, SlayCareerCatalog.Challenge challenge, String period) {
        String scope = " FROM slay_solo_bests b JOIN users u ON u.id=b.user_id WHERE b.challenge_id=:c AND b.period=:p";
        Mono<Map<String, Object>> totals =
                db.sql(
                                "SELECT count(*) AS total,"
                                        + " max(b.best_score) FILTER (WHERE b.user_id=:u) AS mine"
                                        + scope)
                        .bind("u", user)
                        .bind("c", challenge.id())
                        .bind("p", period)
                        .fetch()
                        .one();
        Mono<Long> better =
                db.sql(
                                "SELECT count(*) AS n"
                                        + scope
                                        + " AND b.best_score > (SELECT best_score FROM"
                                        + " slay_solo_bests WHERE user_id=:u AND challenge_id=:c"
                                        + " AND period=:p)")
                        .bind("u", user)
                        .bind("c", challenge.id())
                        .bind("p", period)
                        .map(r -> r.get("n", Long.class))
                        .one();
        Mono<List<Map<String, Object>>> top =
                rows(
                        "SELECT u.username,b.best_score,b.user_id"
                                + scope
                                + " ORDER BY b.best_score DESC,b.updated_at LIMIT 10",
                        user,
                        challenge.id(),
                        period);
        Mono<List<Map<String, Object>>> friends =
                rows(
                        "SELECT u.username,b.best_score,b.user_id"
                                + scope
                                + " AND (b.user_id=:u OR b.user_id IN (SELECT CASE WHEN"
                                + " f.low_user_id=:u THEN f.high_user_id ELSE f.low_user_id END"
                                + " FROM friends f WHERE f.status='"
                                + FriendRow.ACCEPTED
                                + "' AND (f.low_user_id=:u OR f.high_user_id=:u)))"
                                + " ORDER BY b.best_score DESC,b.updated_at LIMIT 50",
                        user,
                        challenge.id(),
                        period);
        return Mono.zip(totals, better, top, friends)
                .map(
                        t -> {
                            long total = ((Number) t.getT1().get("total")).longValue();
                            Number mine = (Number) t.getT1().get("mine");
                            Map<String, Object> global = new LinkedHashMap<>();
                            global.put("total", total);
                            global.put("rank", mine == null ? null : t.getT2() + 1);
                            global.put(
                                    "topPercent",
                                    mine == null
                                            ? null
                                            : (int) Math.ceil(100.0 * (t.getT2() + 1) / total));
                            global.put("top", t.getT3());
                            Map<String, Object> result = new LinkedHashMap<>();
                            result.put("challengeId", challenge.id());
                            result.put("title", challenge.title());
                            result.put("period", period);
                            result.put("personalBest", mine == null ? null : mine.doubleValue());
                            result.put("global", global);
                            result.put("friends", t.getT4());
                            int position = 0;
                            for (var row : t.getT4()) {
                                position++;
                                if (Boolean.TRUE.equals(row.get("me")))
                                    result.put("friendsRank", position);
                            }
                            return result;
                        });
    }

    private Mono<List<Map<String, Object>>> rows(
            String sql, UUID user, String challenge, String period) {
        var spec = db.sql(sql);
        if (sql.contains(":u")) spec = spec.bind("u", user);
        return spec.bind("c", challenge)
                .bind("p", period)
                .map(
                        r -> {
                            Map<String, Object> m = new LinkedHashMap<>();
                            m.put("username", r.get("username", String.class));
                            m.put("score", r.get("best_score", Double.class));
                            m.put("me", user.equals(r.get("user_id", UUID.class)));
                            return m;
                        })
                .all()
                .collectList();
    }
}
