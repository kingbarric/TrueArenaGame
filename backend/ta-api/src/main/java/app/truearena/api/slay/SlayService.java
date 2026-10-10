package app.truearena.api.slay;

import app.truearena.api.coins.CoinService;
import app.truearena.api.competitive.RatingService;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.room.RoomService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.engine.slay.*;
import app.truearena.engine.slay.SlayRules.*;
import app.truearena.persistence.UserRepository;

import com.fasterxml.jackson.databind.ObjectMapper;

import io.r2dbc.postgresql.codec.Json;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.ReactiveTransactionManager;
import org.springframework.transaction.reactive.TransactionalOperator;

import reactor.core.publisher.*;
import reactor.core.scheduler.Schedulers;

import java.time.*;
import java.util.*;
import java.util.function.Function;

@Service
public class SlayService {
    private final DatabaseClient db;
    private final ObjectMapper json;
    private final SlayCatalog catalog;
    private final UserRepository users;
    private final CoinService coins;
    private final ObjectProvider<RoomService> rooms;
    private final RatingService ratings;
    private final TransactionalOperator tx;

    @org.springframework.beans.factory.annotation.Autowired
    private app.truearena.room.RoomRuntimeRegistry runtimes;

    @org.springframework.beans.factory.annotation.Autowired
    private ObjectProvider<app.truearena.api.championship.ChampionshipService> championships;

    @org.springframework.beans.factory.annotation.Autowired
    private app.truearena.api.push.PushNotificationService notifications;

    @org.springframework.beans.factory.annotation.Autowired
    private app.truearena.api.competitive.CompetitiveProfileService competitiveProfiles;

    @org.springframework.beans.factory.annotation.Autowired
    private app.truearena.api.competitive.CompetitiveSettings competitive;

    public SlayService(
            DatabaseClient db,
            ObjectMapper json,
            SlayCatalog catalog,
            UserRepository users,
            CoinService coins,
            ObjectProvider<RoomService> rooms,
            RatingService ratings,
            ReactiveTransactionManager manager) {
        this.db = db;
        this.json = json;
        this.catalog = catalog;
        this.users = users;
        this.coins = coins;
        this.rooms = rooms;
        this.ratings = ratings;
        tx = TransactionalOperator.create(manager);
    }

    /**
     * Slay rating is off unless {@code slayhuud} is listed in
     * {@code truearena.competitive.rated-game-types}: popularity votes on
     * client-rendered snapshots are not yet trustworthy enough to move a rating.
     */
    private boolean ratingEnabled() {
        return competitive.isRated("slayhuud") && !catalog.manifest().developmentAssets();
    }

    private boolean rated(SlayCompetition c) {
        return c.eligibleRating && ratingEnabled();
    }

    public record Create(
            String mode, String themeId, int seats, String contestantBody, boolean ranked) {}

    public record SavedLook(UUID id, Look look, int catalogVersion, String snapshotUrl) {}

    public record Submit(UUID lookId) {}

    public record Join(String role, String body) {}

    public record Ballot(
            UUID id, String theme, String entryA, String entryB, String imageA, String imageB) {}

    private String write(Object value) {
        try {
            return json.writeValueAsString(value);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private <T> T read(String value, Class<T> type) {
        try {
            return json.readValue(value, type);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static void check(boolean ok, String message) {
        if (!ok) throw ApiExceptions.badRequest(message);
    }

    private Mono<Void> verified(UUID user) {
        return users.findById(user)
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("Unknown user")))
                .flatMap(
                        u ->
                                u.isGuest() || u.isBot()
                                        ? Mono.error(
                                                ApiExceptions.forbidden(
                                                        "Use a verified account to compete or"
                                                                + " vote"))
                                        : Mono.empty());
    }

    public Mono<Set<String>> wardrobe(UUID user) {
        return db.sql("SELECT item_id FROM slay_wardrobe WHERE user_id=:u")
                .bind("u", user)
                .map(r -> r.get("item_id", String.class))
                .all()
                .collect(java.util.stream.Collectors.toSet())
                .map(
                        ids -> {
                            catalog.manifest().items().stream()
                                    .filter(Item::isDefault)
                                    .forEach(i -> ids.add(i.id()));
                            return ids;
                        });
    }

    public Mono<Map<String, Object>> profile(UUID user) {
        return db.sql("SELECT xp,avatar FROM slay_profiles WHERE user_id=:u")
                .bind("u", user)
                .map(
                        r -> {
                            Map<String, Object> p = new LinkedHashMap<>();
                            p.put("xp", r.get("xp", Integer.class));
                            Json avatar = r.get("avatar", Json.class);
                            p.put(
                                    "avatar",
                                    avatar == null ? null : read(avatar.asString(), Look.class));
                            return p;
                        })
                .one()
                .defaultIfEmpty(new LinkedHashMap<>(Map.of("xp", 0)))
                .zipWith(wardrobe(user))
                .map(
                        t -> {
                            t.getT1().put("owned", t.getT2());
                            t.getT1().put("rated", ratingEnabled());
                            return t.getT1();
                        })
                .flatMap(
                        profile ->
                                db.sql(
                                                "SELECT count(*) AS competitions,count(*)"
                                                    + " FILTER(WHERE p.outcome='won') AS"
                                                    + " wins,count(*) FILTER(WHERE p.placement<=3)"
                                                    + " AS top_three FROM match_participants p JOIN"
                                                    + " match_records m ON p.match_id=m.id WHERE"
                                                    + " p.user_id=:u AND m.game_type='slayhuud'")
                                        .bind("u", user)
                                        .fetch()
                                        .one()
                                        .map(
                                                stats -> {
                                                    profile.put(
                                                            "stats", new LinkedHashMap<>(stats));
                                                    return profile;
                                                }))
                .flatMap(
                        profile ->
                                db.sql(
                                                "SELECT count(*) AS competitions,count(*)"
                                                    + " FILTER(WHERE (e->>'placement')::int=1) AS"
                                                    + " wins,count(*) FILTER(WHERE"
                                                    + " (e->>'placement')::int<=3) AS top_three"
                                                    + " FROM slay_competitions c CROSS JOIN LATERAL"
                                                    + " jsonb_array_elements(c.state->'entries') e"
                                                    + " WHERE c.mode IN('daily','weekly') AND"
                                                    + " c.status='results' AND e->>'userId'=:u")
                                        .bind("u", user.toString())
                                        .fetch()
                                        .one()
                                        .map(
                                                async -> {
                                                    Map<String, Object> stats =
                                                            (Map<String, Object>)
                                                                    profile.get("stats");
                                                    async.forEach(
                                                            (key, value) ->
                                                                    stats.put(
                                                                            key,
                                                                            ((Number)
                                                                                                    stats
                                                                                                            .getOrDefault(
                                                                                                                    key,
                                                                                                                    0L))
                                                                                            .longValue()
                                                                                    + ((Number)
                                                                                                    value)
                                                                                            .longValue()));
                                                    return profile;
                                                }))
                .flatMap(
                        profile ->
                                competitiveProfiles
                                        .profileOf(user, true)
                                        .map(
                                                p -> {
                                                    p.games().stream()
                                                            .filter(
                                                                    g ->
                                                                            g.gameType()
                                                                                    .equals(
                                                                                            "slayhuud"))
                                                            .findFirst()
                                                            .ifPresent(
                                                                    g ->
                                                                            profile.put(
                                                                                    "competitive",
                                                                                    g));
                                                    return profile;
                                                }));
    }

    public Mono<Void> buy(UUID user, String itemId) {
        return tx.transactional(
                Mono.defer(
                        () -> {
                            Item item = catalog.items().get(itemId);
                            check(
                                    item != null && !item.isDefault() && item.coinCost() > 0,
                                    "Item is unavailable for purchase");
                            return db.sql(
                                            "INSERT INTO slay_profiles(user_id) VALUES(:u) ON"
                                                    + " CONFLICT DO NOTHING")
                                    .bind("u", user)
                                    .fetch()
                                    .rowsUpdated()
                                    .then(
                                            db.sql(
                                                            "SELECT user_id FROM slay_profiles"
                                                                + " WHERE user_id=:u FOR UPDATE")
                                                    .bind("u", user)
                                                    .fetch()
                                                    .one())
                                    .then(wardrobe(user))
                                    .flatMap(
                                            owned -> {
                                                check(
                                                        !owned.contains(itemId),
                                                        "You already own this item");
                                                return coins.debit(
                                                                user,
                                                                item.coinCost(),
                                                                "slay_wardrobe",
                                                                null)
                                                        .then(
                                                                db.sql(
                                                                                "INSERT INTO"
                                                                                    + " slay_wardrobe(user_id,item_id,source)"
                                                                                    + " VALUES(:u,:i,'purchase')")
                                                                        .bind("u", user)
                                                                        .bind("i", itemId)
                                                                        .fetch()
                                                                        .rowsUpdated()
                                                                        .then());
                                            });
                        }));
    }

    public Mono<SavedLook> saveLook(UUID user, Look look) {
        return wardrobe(user)
                .flatMap(
                        owned -> {
                            var m = catalog.manifest();
                            SlayRules.validate(
                                    look,
                                    catalog.items(),
                                    owned,
                                    Set.copyOf(m.skinTones()),
                                    Set.copyOf(m.facePresets()),
                                    Set.copyOf(m.poses()),
                                    Set.copyOf(m.backgrounds()));
                            UUID id = UUID.randomUUID();
                            return tx.transactional(
                                    db.sql(
                                                    "INSERT INTO"
                                                        + " slay_looks(id,user_id,look,catalog_version)"
                                                        + " VALUES(:id,:u,:l,:v)")
                                            .bind("id", id)
                                            .bind("u", user)
                                            .bind("l", Json.of(write(look)))
                                            .bind("v", m.version())
                                            .fetch()
                                            .rowsUpdated()
                                            .then(
                                                    db.sql(
                                                                    "INSERT INTO"
                                                                        + " slay_profiles(user_id,avatar)"
                                                                        + " VALUES(:u,:l) ON"
                                                                        + " CONFLICT(user_id) DO"
                                                                        + " UPDATE SET"
                                                                        + " avatar=:l,updated_at=now()")
                                                            .bind("u", user)
                                                            .bind("l", Json.of(write(look)))
                                                            .fetch()
                                                            .rowsUpdated())
                                            .thenReturn(
                                                    new SavedLook(id, look, m.version(), null)));
                        });
    }

    private Mono<SavedLook> look(UUID user, UUID id) {
        return db.sql(
                        "SELECT id,look,catalog_version,snapshot IS NOT NULL AS has_image FROM"
                                + " slay_looks WHERE id=:id AND user_id=:u")
                .bind("id", id)
                .bind("u", user)
                .map(
                        r ->
                                new SavedLook(
                                        id,
                                        read(r.get("look", Json.class).asString(), Look.class),
                                        r.get("catalog_version", Integer.class),
                                        Boolean.TRUE.equals(r.get("has_image", Boolean.class))
                                                ? "/slay/looks/" + id + "/snapshot"
                                                : null))
                .one()
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("Look not found")));
    }

    /** A 600×900 JPEG at quality 0.85 is ~100 KB; this leaves generous headroom. */
    public static final int MAX_SNAPSHOT_BYTES = 512 * 1024;

    private static final byte[] PNG_MAGIC = {(byte) 137, 80, 78, 71, 13, 10, 26, 10};

    /** Looks saved before the switch to JPEG are PNG; serve each with its own type. */
    public static org.springframework.http.MediaType snapshotType(byte[] bytes) {
        return bytes.length >= 8 && Arrays.equals(Arrays.copyOf(bytes, 8), PNG_MAGIC)
                ? org.springframework.http.MediaType.IMAGE_PNG
                : org.springframework.http.MediaType.IMAGE_JPEG;
    }

    public Mono<Void> snapshot(UUID user, UUID id, byte[] bytes) {
        return Mono.fromCallable(
                        () -> {
                            check(
                                    bytes.length >= 4 && bytes.length <= MAX_SNAPSHOT_BYTES,
                                    "Image must be at most 512 KB");
                            check(
                                    (bytes[0] & 0xff) == 0xff
                                            && (bytes[1] & 0xff) == 0xd8
                                            && (bytes[2] & 0xff) == 0xff,
                                    "JPEG image required");
                            var image =
                                    javax.imageio.ImageIO.read(
                                            new java.io.ByteArrayInputStream(bytes));
                            check(image != null, "Invalid image");
                            check(
                                    image.getWidth() <= 1024 && image.getHeight() <= 1536,
                                    "Invalid image dimensions");
                            return bytes;
                        })
                .subscribeOn(Schedulers.boundedElastic())
                .flatMap(
                        image ->
                                look(user, id)
                                        .flatMap(
                                                l ->
                                                        db.sql(
                                                                        "UPDATE slay_looks SET"
                                                                            + " snapshot=:p WHERE"
                                                                            + " id=:id AND"
                                                                            + " user_id=:u AND"
                                                                            + " snapshot IS NULL"
                                                                            + " AND NOT EXISTS"
                                                                            + " (SELECT 1 FROM"
                                                                            + " slay_competitions c"
                                                                            + " WHERE"
                                                                            + " c.state->'entries'"
                                                                            + " @> :entry)")
                                                                .bind("p", image)
                                                                .bind("id", id)
                                                                .bind("u", user)
                                                                .bind(
                                                                        "entry",
                                                                        Json.of(
                                                                                "[{\"lookId\":\""
                                                                                        + id
                                                                                        + "\"}]"))
                                                                .fetch()
                                                                .rowsUpdated()
                                                                .flatMap(
                                                                        n ->
                                                                                n == 1
                                                                                        ? Mono
                                                                                                .empty()
                                                                                        : Mono
                                                                                                .error(
                                                                                                        ApiExceptions
                                                                                                                .conflict(
                                                                                                                        "Submitted"
                                                                                                                            + " look"
                                                                                                                            + " images"
                                                                                                                            + " are immutable")))));
    }

    public record RunwayLook(Look look, int catalogVersion) {}

    public Mono<RunwayLook> runwayLook(UUID viewer, UUID id) {
        return visibleLook(
                viewer,
                id,
                db.sql(
                                "SELECT look,catalog_version FROM slay_looks WHERE id=:id AND"
                                    + " snapshot IS NOT NULL")
                        .bind("id", id)
                        .map(
                                r ->
                                        new RunwayLook(
                                                read(
                                                        r.get("look", Json.class).asString(),
                                                        Look.class),
                                                r.get("catalog_version", Integer.class)))
                        .one());
    }

    public Mono<byte[]> image(UUID viewer, UUID id) {
        return visibleLook(viewer, id, image(id));
    }

    private <T> Mono<T> visibleLook(UUID viewer, UUID id, Mono<T> content) {
        return db.sql("SELECT user_id FROM slay_looks WHERE id=:id")
                .bind("id", id)
                .map(r -> r.get("user_id", UUID.class))
                .one()
                .flatMap(
                        owner ->
                                owner.equals(viewer)
                                        ? content
                                        : db.sql(
                                                        "SELECT state FROM slay_competitions WHERE"
                                                            + " status"
                                                            + " IN('voting','round_result','results')"
                                                            + " AND state->'entries' @> :look")
                                                .bind(
                                                        "look",
                                                        Json.of("[{\"lookId\":\"" + id + "\"}]"))
                                                .map(
                                                        r ->
                                                                read(
                                                                        r.get("state", Json.class)
                                                                                .asString(),
                                                                        SlayCompetition.class))
                                                .all()
                                                .filter(
                                                        c ->
                                                                c.status.equals("results")
                                                                        || c
                                                                                .currentEntries()
                                                                                .stream()
                                                                                .anyMatch(
                                                                                        e ->
                                                                                                e
                                                                                                                .lookId
                                                                                                                .equals(
                                                                                                                        id
                                                                                                                                .toString())
                                                                                                        && (!c
                                                                                                                        .isElimination()
                                                                                                                || !c
                                                                                                                        .status
                                                                                                                        .equals(
                                                                                                                                "voting")
                                                                                                                || c.currentEntries()
                                                                                                                                .size()
                                                                                                                        == 2
                                                                                                                || c
                                                                                                                                        .revealed()
                                                                                                                                != null
                                                                                                                        && c.revealed()
                                                                                                                                .id
                                                                                                                                .equals(
                                                                                                                                        e.id))))
                                                .concatMap(c -> allowed(viewer, c))
                                                .filter(Boolean::booleanValue)
                                                .next()
                                                .flatMap(ok -> content))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("Look unavailable")));
    }

    public Mono<byte[]> image(UUID id) {
        return db.sql("SELECT snapshot FROM slay_looks WHERE id=:id AND snapshot IS NOT NULL")
                .bind("id", id)
                .map(r -> r.get("snapshot", byte[].class))
                .one()
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("Image not found")));
    }

    public Mono<Score> solo(UUID user, String theme, UUID id) {
        return tx.transactional(
                look(user, id)
                        .flatMap(
                                l -> {
                                    Score score =
                                            SlayRules.score(
                                                    l.look(),
                                                    catalog.theme(theme),
                                                    catalog.items());
                                    String ref =
                                            "solo:" + theme + ":" + LocalDate.now(ZoneOffset.UTC);
                                    return claim(user, ref)
                                            .flatMap(
                                                    newClaim ->
                                                            newClaim
                                                                    ? coins.credit(
                                                                                    user,
                                                                                    score.stars()
                                                                                                    * 5L
                                                                                            + 5,
                                                                                    "slay_solo",
                                                                                    id)
                                                                            .then(
                                                                                    xp(
                                                                                            user,
                                                                                            20
                                                                                                    + score
                                                                                                                    .stars()
                                                                                                            * 10))
                                                                    : Mono.empty())
                                            .thenReturn(score);
                                }));
    }

    private Mono<Boolean> claim(UUID user, String ref) {
        return db.sql(
                        "INSERT INTO slay_reward_claims(user_id,ref) VALUES(:u,:r) ON CONFLICT DO"
                                + " NOTHING")
                .bind("u", user)
                .bind("r", ref)
                .fetch()
                .rowsUpdated()
                .map(n -> n == 1);
    }

    private Mono<Void> xp(UUID user, int points) {
        return db.sql(
                        "INSERT INTO slay_profiles(user_id,xp) VALUES(:u,:x) ON CONFLICT(user_id)"
                                + " DO UPDATE SET xp=slay_profiles.xp+:x,updated_at=now()")
                .bind("u", user)
                .bind("x", points)
                .fetch()
                .rowsUpdated()
                .then();
    }

    public Mono<Map<String, Object>> create(UUID user, Create request) {
        return verified(user)
                .then(
                        Mono.defer(
                                () -> {
                                    String mode = request.mode();
                                    check(
                                            mode != null
                                                    && Set.of("battle", "group", "slay_or_pass")
                                                            .contains(mode),
                                            "Choose a live competition mode");
                                    int seats = "battle".equals(mode) ? 2 : request.seats();
                                    check(
                                            Set.of(2, 4, 6, 8, 10, 16).contains(seats)
                                                    && (mode.equals("battle") || seats >= 4),
                                            "Invalid group size");
                                    String body =
                                            request.contestantBody() == null
                                                    ? "male"
                                                    : request.contestantBody();
                                    check(
                                            Set.of("male", "female").contains(body),
                                            "Choose an avatar body");
                                    Theme selectedTheme = catalog.theme(request.themeId());
                                    if (mode.equals("slay_or_pass"))
                                        check(
                                                selectedTheme.bodyEligibility().contains(body),
                                                "Choose a contestant avatar eligible for this"
                                                        + " theme");
                                    return rooms.getObject()
                                            .create(
                                                    user,
                                                    null,
                                                    "slayhuud",
                                                    0L,
                                                    Map.of(
                                                            "mode",
                                                            mode,
                                                            "themeId",
                                                            request.themeId(),
                                                            "seats",
                                                            mode.equals("slay_or_pass")
                                                                    ? seats + 6
                                                                    : seats,
                                                            "contestantBody",
                                                            body),
                                                    request.ranked())
                                            .flatMap(room -> ensureRoom(user, room.id()))
                                            .flatMap(c -> view(user, c));
                                }));
    }

    private Mono<SlayCompetition> load(UUID id, boolean lock) {
        return db.sql(
                        "SELECT state FROM slay_competitions WHERE id=:id"
                                + (lock ? " FOR UPDATE" : ""))
                .bind("id", id)
                .map(r -> read(r.get("state", Json.class).asString(), SlayCompetition.class))
                .one()
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("Competition not found")));
    }

    private Mono<Void> save(SlayCompetition c) {
        var sql =
                db.sql(
                                "UPDATE slay_competitions SET state=:s,status=:status,deadline=:d"
                                        + " WHERE id=:id")
                        .bind("s", Json.of(write(c)))
                        .bind("status", c.status)
                        .bind("id", UUID.fromString(c.id));
        sql = c.deadline == null ? sql.bindNull("d", Instant.class) : sql.bind("d", c.deadline);
        return sql.fetch().rowsUpdated().then();
    }

    private Mono<SlayCompetition> insert(SlayCompetition c) {
        var sql =
                db.sql(
                                "INSERT INTO"
                                    + " slay_competitions(id,room_id,host_id,mode,state,status,deadline)"
                                    + " VALUES(:id,:r,:h,:m,:s,:st,:d) ON CONFLICT DO NOTHING")
                        .bind("id", UUID.fromString(c.id))
                        .bind("m", c.mode)
                        .bind("s", Json.of(write(c)))
                        .bind("st", c.status);
        sql =
                c.roomId == null
                        ? sql.bindNull("r", UUID.class)
                        : sql.bind("r", UUID.fromString(c.roomId));
        sql =
                c.hostId == null
                        ? sql.bindNull("h", UUID.class)
                        : sql.bind("h", UUID.fromString(c.hostId));
        sql = c.deadline == null ? sql.bindNull("d", Instant.class) : sql.bind("d", c.deadline);
        return sql.fetch().rowsUpdated().then(load(UUID.fromString(c.id), false));
    }

    public Mono<SlayCompetition> ensureRoom(UUID user, UUID roomId) {
        Mono<SlayCompetition> existing =
                db.sql("SELECT state FROM slay_competitions WHERE room_id=:r")
                        .bind("r", roomId)
                        .map(
                                r ->
                                        read(
                                                r.get("state", Json.class).asString(),
                                                SlayCompetition.class))
                        .one();
        return existing.switchIfEmpty(
                Mono.defer(
                        () ->
                                rooms.getObject()
                                        .get(roomId, user)
                                        .flatMap(
                                                room ->
                                                        roomConfiguration(roomId)
                                                                .flatMap(
                                                                        cfg ->
                                                                                insert(
                                                                                        competitionFor(
                                                                                                room,
                                                                                                cfg))))));
    }

    private Mono<Map<String, Object>> roomConfiguration(UUID roomId) {
        return db.sql("SELECT game_config FROM rooms WHERE id=:r")
                .bind("r", roomId)
                .map(
                        r -> {
                            String config = r.get("game_config", String.class);
                            return config == null
                                    ? Map.<String, Object>of()
                                    : (Map<String, Object>) read(config, Map.class);
                        })
                .one()
                .defaultIfEmpty(Map.of());
    }

    private SlayCompetition competitionFor(RoomView room, Map<String, Object> cfg) {
        check("slayhuud".equals(room.gameType()), "This is not a SlayHuud room");
        SlayCompetition c = new SlayCompetition();
        c.id = room.id().toString();
        c.roomId = c.id;
        c.hostId = room.hostId().toString();
        c.mode = String.valueOf(cfg.getOrDefault("mode", "battle"));
        check(Set.of("battle", "group", "slay_or_pass").contains(c.mode), "Unknown SlayHuud mode");
        c.themeId = String.valueOf(cfg.getOrDefault("themeId", "first-date"));
        c.seats = cfg.get("seats") instanceof Number n ? n.intValue() : 2;
        if (c.isElimination()) c.seats -= 6;
        check(
                c.mode.equals("battle") ? c.seats == 2 : Set.of(4, 6, 8, 10, 16).contains(c.seats),
                "Invalid SlayHuud group size");
        c.contestantBody = String.valueOf(cfg.getOrDefault("contestantBody", "male"));
        check(Set.of("male", "female").contains(c.contestantBody), "Choose an avatar body");
        c.requestedRanked = room.ranked();
        Theme t = catalog.theme(c.themeId);
        c.stylingSeconds = t.stylingSeconds();
        c.votingSeconds = t.votingSeconds();
        c.systemWeight = t.systemWeight();
        c.minVotes = t.minVotes();
        if (c.isElimination())
            check(
                    t.bodyEligibility().contains(c.contestantBody),
                    "Choose a contestant avatar eligible for this theme");
        c.roundThemes = List.of(c.themeId, "wedding-guest", "red-carpet", "african-royalty");
        c.deadline = Instant.now().plusSeconds(3600);
        return c;
    }

    public Mono<Void> startTournament(UUID roomId) {
        return db.sql("SELECT host_id FROM rooms WHERE id=:id")
                .bind("id", roomId)
                .map(r -> r.get("host_id", UUID.class))
                .one()
                .flatMap(
                        host ->
                                ensureRoom(host, roomId)
                                        .flatMap(
                                                c -> {
                                                    if (!"lobby".equals(c.status))
                                                        return Mono.empty();
                                                    return db.sql(
                                                                    "SELECT user_id FROM"
                                                                            + " room_members WHERE"
                                                                            + " room_id=:r ORDER BY"
                                                                            + " user_id")
                                                            .bind("r", roomId)
                                                            .map(r -> r.get("user_id", UUID.class))
                                                            .all()
                                                            .concatMap(
                                                                    user ->
                                                                            profile(user)
                                                                                    .flatMap(
                                                                                            p ->
                                                                                                    join(
                                                                                                            user,
                                                                                                            UUID
                                                                                                                    .fromString(
                                                                                                                            c.id),
                                                                                                            new Join(
                                                                                                                    "contestant",
                                                                                                                    p
                                                                                                                                            .get(
                                                                                                                                                    "avatar")
                                                                                                                                    instanceof
                                                                                                                                    Look
                                                                                                                                                    l
                                                                                                                            ? l
                                                                                                                                    .body()
                                                                                                                            : "female"))))
                                                            .then(
                                                                    start(
                                                                            host,
                                                                            UUID.fromString(c.id)))
                                                            .then();
                                                }));
    }

    public Mono<Map<String, Object>> forRoom(UUID user, UUID room) {
        return ensureRoom(user, room).flatMap(c -> view(user, c));
    }

    public Mono<Map<String, Object>> get(UUID user, UUID id) {
        return mutate(id, c -> Mono.just(c)).flatMap(c -> view(user, c));
    }

    private Mono<SlayCompetition> mutate(
            UUID id, Function<SlayCompetition, Mono<SlayCompetition>> change) {
        return tx.transactional(
                        load(id, true)
                                .publishOn(Schedulers.boundedElastic())
                                .flatMap(
                                        c -> {
                                            c.tick(Instant.now());
                                            return change.apply(c);
                                        })
                                .flatMap(c -> save(c).then(settle(c)).thenReturn(c)))
                .doOnSuccess(
                        c -> {
                            if (c.roomId != null)
                                runtimes.find(UUID.fromString(c.roomId))
                                        .ifPresent(
                                                rt ->
                                                        rt.bus.tryEmitNext(
                                                                new app.truearena.room
                                                                        .LobbyBroadcast(
                                                                        "SLAY_CHANGED",
                                                                        Map.of(
                                                                                "competitionId",
                                                                                c.id))));
                        });
    }

    public Mono<Map<String, Object>> join(UUID user, UUID id, Join request) {
        return verified(user)
                .then(
                        mutate(
                                id,
                                c -> {
                                    check(
                                            c.status.equals("lobby")
                                                    || c.isAsync() && c.status.equals("styling"),
                                            "This competition is already running");
                                    check(
                                            request.body() != null
                                                    && Set.of("male", "female")
                                                            .contains(request.body()),
                                            "Choose your avatar");
                                    String role =
                                            request.role() == null ? "contestant" : request.role();
                                    if (role.equals("contestant"))
                                        check(
                                                catalog.theme(c.currentTheme())
                                                        .bodyEligibility()
                                                        .contains(request.body()),
                                                "Choose an eligible avatar for this theme");
                                    check(
                                            Set.of("judge", "contestant").contains(role),
                                            "Unknown role");
                                    check(
                                            c.isElimination() || role.equals("contestant"),
                                            "This mode has no judge seats");
                                    var previous =
                                            c.members.stream()
                                                    .filter(m -> m.userId().equals(user.toString()))
                                                    .findFirst()
                                                    .orElse(null);
                                    if (previous != null) {
                                        check(
                                                previous.role().equals(role),
                                                "Your room role is already set");
                                        return Mono.just(c);
                                    }
                                    if (c.isElimination())
                                        check(
                                                role.equals("contestant")
                                                        ? request.body().equals(c.contestantBody)
                                                        : !request.body().equals(c.contestantBody),
                                                "Choose the avatar body for your room role");
                                    check(
                                            role.equals("judge")
                                                    ? c.judges().size() < 6
                                                    : c.contestants().size() < c.seats,
                                            "All seats are taken");
                                    Mono<Void> membership =
                                            c.roomId == null
                                                    ? Mono.empty()
                                                    : rooms.getObject()
                                                            .get(UUID.fromString(c.roomId), user)
                                                            .flatMap(
                                                                    room ->
                                                                            room.members().stream()
                                                                                            .anyMatch(
                                                                                                    m ->
                                                                                                            m.userId()
                                                                                                                    .equals(
                                                                                                                            user))
                                                                                    ? Mono.empty()
                                                                                    : rooms.getObject()
                                                                                            .join(
                                                                                                    room
                                                                                                            .code(),
                                                                                                    user,
                                                                                                    null)
                                                                                            .then());
                                    return db.sql(
                                                    "SELECT blocked_id FROM user_blocks WHERE"
                                                        + " (blocker_id=:u AND"
                                                        + " blocked_id=ANY(:ids)) OR (blocked_id=:u"
                                                        + " AND blocker_id=ANY(:ids))")
                                            .bind("u", user)
                                            .bind(
                                                    "ids",
                                                    c.members.stream()
                                                            .map(m -> UUID.fromString(m.userId()))
                                                            .toArray(UUID[]::new))
                                            .fetch()
                                            .first()
                                            .hasElement()
                                            .flatMap(
                                                    blocked -> {
                                                        check(
                                                                !blocked,
                                                                "This room is unavailable because"
                                                                    + " of a blocked relationship");
                                                        return membership;
                                                    })
                                            .then(
                                                    Mono.fromSupplier(
                                                            () -> {
                                                                c.members.add(
                                                                        new SlayCompetition.Member(
                                                                                user.toString(),
                                                                                role,
                                                                                request.body()));
                                                                return c;
                                                            }));
                                }))
                .flatMap(c -> view(user, c));
    }

    public Mono<Map<String, Object>> start(UUID user, UUID id) {
        return verified(user)
                .then(
                        mutate(
                                id,
                                c -> {
                                    check(
                                            user.toString().equals(c.hostId),
                                            "Only the host can start");
                                    c.start(Instant.now());
                                    return db.sql("UPDATE rooms SET status='in_game' WHERE id=:r")
                                            .bind("r", UUID.fromString(c.roomId))
                                            .fetch()
                                            .rowsUpdated()
                                            .then(
                                                    db.sql(
                                                                    "INSERT INTO"
                                                                        + " game_sessions(id,room_id,game_type,config,catalog_version,rng_seed,phase,round)"
                                                                        + " VALUES(:id,:r,'slayhuud',:config,:v,0,'Styling',1)"
                                                                        + " ON CONFLICT DO NOTHING")
                                                            .bind("id", UUID.fromString(c.id))
                                                            .bind("r", UUID.fromString(c.roomId))
                                                            .bind("config", Json.of(write(c)))
                                                            .bind("v", catalog.manifest().version())
                                                            .fetch()
                                                            .rowsUpdated())
                                            .thenReturn(c);
                                }))
                .flatMap(c -> view(user, c));
    }

    public Mono<Map<String, Object>> submit(UUID user, UUID id, UUID lookId) {
        return mutate(
                        id,
                        c ->
                                look(user, lookId)
                                        .map(
                                                l -> {
                                                    check(
                                                            l.catalogVersion()
                                                                    == catalog.manifest().version(),
                                                            "Re-save your look using the current"
                                                                    + " wardrobe");
                                                    check(
                                                            l.snapshotUrl() != null,
                                                            "Save the look image before entering");
                                                    if (c.isElimination())
                                                        check(
                                                                l.look()
                                                                        .body()
                                                                        .equals(c.contestantBody),
                                                                "The avatar body must match your"
                                                                        + " contestant pool");
                                                    Score score =
                                                            SlayRules.score(
                                                                    l.look(),
                                                                    catalog.theme(c.currentTheme()),
                                                                    catalog.items());
                                                    c.submit(
                                                            new SlayCompetition.Entry(
                                                                    UUID.randomUUID().toString(),
                                                                    user.toString(),
                                                                    lookId.toString(),
                                                                    c.round,
                                                                    score),
                                                            Instant.now());
                                                    return c;
                                                }))
                .flatMap(c -> view(user, c));
    }

    public Mono<Map<String, Object>> judge(UUID user, UUID id, String entry, boolean slay) {
        return verified(user)
                .then(
                        mutate(
                                id,
                                c -> {
                                    c.judge(user.toString(), entry, slay, Instant.now());
                                    return Mono.just(c);
                                }))
                .flatMap(c -> view(user, c));
    }

    public Mono<Map<String, Object>> finalVote(UUID user, UUID id, String entry) {
        return verified(user)
                .then(
                        mutate(
                                id,
                                c -> {
                                    c.finalVote(user.toString(), entry, Instant.now());
                                    return Mono.just(c);
                                }))
                .flatMap(c -> view(user, c));
    }

    public Mono<Map<String, Object>> cancel(UUID user, UUID id) {
        return mutate(
                        id,
                        c -> {
                            check(user.toString().equals(c.hostId), "Only the host can cancel");
                            check(
                                    c.status.equals("lobby"),
                                    "A running competition cannot be cancelled by its host");
                            c.status = "cancelled";
                            c.deadline = null;
                            return rooms.getObject()
                                    .abandon(UUID.fromString(c.roomId), user)
                                    .thenReturn(c);
                        })
                .flatMap(c -> view(user, c));
    }

    public Mono<Ballot> ballot(UUID user, UUID id) {
        return verified(user)
                .then(load(id, false).flatMap(c -> allowed(user, c)))
                .flatMap(
                        ok -> {
                            check(ok, "Private championship match");
                            return tx.transactional(
                                    load(id, true)
                                            .flatMap(
                                                    c -> {
                                                        check(
                                                                c.status.equals("voting")
                                                                        && !c.isElimination()
                                                                        && Instant.now()
                                                                                .isBefore(
                                                                                        c.deadline),
                                                                "Voting is closed");
                                                        check(
                                                                c.contestants().stream()
                                                                        .noneMatch(
                                                                                m ->
                                                                                        m.userId()
                                                                                                .equals(
                                                                                                        user
                                                                                                                .toString())),
                                                                "Contestants cannot vote in their"
                                                                        + " own competition");
                                                        return users.findById(user)
                                                                .flatMap(
                                                                        u -> {
                                                                            check(
                                                                                    u.createdAt()
                                                                                            .isBefore(
                                                                                                    Instant
                                                                                                            .now()
                                                                                                            .minusSeconds(
                                                                                                                    3600)),
                                                                                    "Voting opens"
                                                                                        + " one hour"
                                                                                        + " after"
                                                                                        + " account"
                                                                                        + " creation");
                                                                            return db.sql(
                                                                                            "SELECT"
                                                                                                + " blocked_id"
                                                                                                + " FROM"
                                                                                                + " user_blocks"
                                                                                                + " WHERE"
                                                                                                + " blocker_id=:u"
                                                                                                + " UNION"
                                                                                                + " SELECT"
                                                                                                + " blocker_id"
                                                                                                + " FROM"
                                                                                                + " user_blocks"
                                                                                                + " WHERE"
                                                                                                + " blocked_id=:u")
                                                                                    .bind("u", user)
                                                                                    .map(
                                                                                            r ->
                                                                                                    r.get(
                                                                                                                    0,
                                                                                                                    UUID.class)
                                                                                                            .toString())
                                                                                    .all()
                                                                                    .collectList();
                                                                        })
                                                                .flatMap(
                                                                        blocked ->
                                                                                db.sql(
                                                                                                "SELECT"
                                                                                                    + " id,entry_a,entry_b,chosen"
                                                                                                    + " FROM"
                                                                                                    + " slay_ballots"
                                                                                                    + " WHERE"
                                                                                                    + " competition_id=:c"
                                                                                                    + " AND voter_id=:u"
                                                                                                    + " AND round=:round")
                                                                                        .bind(
                                                                                                "c",
                                                                                                id)
                                                                                        .bind(
                                                                                                "u",
                                                                                                user)
                                                                                        .bind(
                                                                                                "round",
                                                                                                c.round)
                                                                                        .fetch()
                                                                                        .all()
                                                                                        .collectList()
                                                                                        .flatMap(
                                                                                                previous -> {
                                                                                                    check(
                                                                                                            previous
                                                                                                                            .size()
                                                                                                                    < 100,
                                                                                                            "You have"
                                                                                                                + " reached"
                                                                                                                + " this"
                                                                                                                + " competition's"
                                                                                                                + " voting"
                                                                                                                + " limit");
                                                                                                    var
                                                                                                            outstanding =
                                                                                                                    previous
                                                                                                                            .stream()
                                                                                                                            .filter(
                                                                                                                                    b ->
                                                                                                                                            b
                                                                                                                                                            .get(
                                                                                                                                                                    "chosen")
                                                                                                                                                    == null)
                                                                                                                            .findFirst()
                                                                                                                            .orElse(
                                                                                                                                    null);
                                                                                                    if (outstanding
                                                                                                            != null)
                                                                                                        return Mono
                                                                                                                .just(
                                                                                                                        ballotView(
                                                                                                                                c,
                                                                                                                                (UUID)
                                                                                                                                        outstanding
                                                                                                                                                .get(
                                                                                                                                                        "id"),
                                                                                                                                outstanding
                                                                                                                                        .get(
                                                                                                                                                "entry_a")
                                                                                                                                        .toString(),
                                                                                                                                outstanding
                                                                                                                                        .get(
                                                                                                                                                "entry_b")
                                                                                                                                        .toString()));
                                                                                                    Set<
                                                                                                                    String>
                                                                                                            served =
                                                                                                                    new HashSet<>();
                                                                                                    previous
                                                                                                            .forEach(
                                                                                                                    b ->
                                                                                                                            served
                                                                                                                                    .add(
                                                                                                                                            b
                                                                                                                                                            .get(
                                                                                                                                                                    "entry_a")
                                                                                                                                                    + ":"
                                                                                                                                                    + b
                                                                                                                                                            .get(
                                                                                                                                                                    "entry_b")));
                                                                                                    List<
                                                                                                                    SlayCompetition
                                                                                                                            .Entry>
                                                                                                            entries =
                                                                                                                    new ArrayList<>(
                                                                                                                            c
                                                                                                                                    .currentEntries()
                                                                                                                                    .stream()
                                                                                                                                    .filter(
                                                                                                                                            e ->
                                                                                                                                                    !blocked
                                                                                                                                                            .contains(
                                                                                                                                                                    e.userId))
                                                                                                                                    .toList());
                                                                                                    Map<
                                                                                                                    String,
                                                                                                                    Long>
                                                                                                            exposure =
                                                                                                                    new HashMap<>();
                                                                                                    c
                                                                                                            .comparisons
                                                                                                            .forEach(
                                                                                                                    v -> {
                                                                                                                        exposure
                                                                                                                                .merge(
                                                                                                                                        v
                                                                                                                                                .a(),
                                                                                                                                        1L,
                                                                                                                                        Long
                                                                                                                                                ::sum);
                                                                                                                        exposure
                                                                                                                                .merge(
                                                                                                                                        v
                                                                                                                                                .b(),
                                                                                                                                        1L,
                                                                                                                                        Long
                                                                                                                                                ::sum);
                                                                                                                    });
                                                                                                    Collections
                                                                                                            .shuffle(
                                                                                                                    entries);
                                                                                                    entries
                                                                                                            .sort(
                                                                                                                    Comparator
                                                                                                                            .comparingLong(
                                                                                                                                    e ->
                                                                                                                                            exposure
                                                                                                                                                    .getOrDefault(
                                                                                                                                                            e.id,
                                                                                                                                                            0L)));
                                                                                                    for (int
                                                                                                                    i =
                                                                                                                            0;
                                                                                                            i
                                                                                                                    < entries
                                                                                                                            .size();
                                                                                                            i++)
                                                                                                        for (int
                                                                                                                        j =
                                                                                                                                i
                                                                                                                                        + 1;
                                                                                                                j
                                                                                                                        < entries
                                                                                                                                .size();
                                                                                                                j++) {
                                                                                                            String
                                                                                                                    a =
                                                                                                                            entries
                                                                                                                                    .get(
                                                                                                                                            i)
                                                                                                                                    .id,
                                                                                                                    b =
                                                                                                                            entries
                                                                                                                                    .get(
                                                                                                                                            j)
                                                                                                                                    .id;
                                                                                                            if (a
                                                                                                                            .compareTo(
                                                                                                                                    b)
                                                                                                                    > 0) {
                                                                                                                String
                                                                                                                        tmp =
                                                                                                                                a;
                                                                                                                a =
                                                                                                                        b;
                                                                                                                b =
                                                                                                                        tmp;
                                                                                                            }
                                                                                                            if (served
                                                                                                                    .contains(
                                                                                                                            a
                                                                                                                                    + ":"
                                                                                                                                    + b))
                                                                                                                continue;
                                                                                                            UUID
                                                                                                                    ballot =
                                                                                                                            UUID
                                                                                                                                    .randomUUID();
                                                                                                            String
                                                                                                                    left =
                                                                                                                            a,
                                                                                                                    right =
                                                                                                                            b;
                                                                                                            return db.sql(
                                                                                                                            "INSERT"
                                                                                                                                + " INTO"
                                                                                                                                + " slay_ballots(id,competition_id,voter_id,round,entry_a,entry_b)"
                                                                                                                                + " VALUES(:id,:c,:u,:r,:a,:b)")
                                                                                                                    .bind(
                                                                                                                            "id",
                                                                                                                            ballot)
                                                                                                                    .bind(
                                                                                                                            "c",
                                                                                                                            id)
                                                                                                                    .bind(
                                                                                                                            "u",
                                                                                                                            user)
                                                                                                                    .bind(
                                                                                                                            "r",
                                                                                                                            c.round)
                                                                                                                    .bind(
                                                                                                                            "a",
                                                                                                                            a)
                                                                                                                    .bind(
                                                                                                                            "b",
                                                                                                                            b)
                                                                                                                    .fetch()
                                                                                                                    .rowsUpdated()
                                                                                                                    .thenReturn(
                                                                                                                            ballotView(
                                                                                                                                    c,
                                                                                                                                    ballot,
                                                                                                                                    left,
                                                                                                                                    right));
                                                                                                        }
                                                                                                    return Mono
                                                                                                            .empty();
                                                                                                }));
                                                    }));
                        });
    }

    private Ballot ballotView(SlayCompetition c, UUID id, String a, String b) {
        var entries = c.currentEntries();
        String imageA =
                entries.stream()
                        .filter(e -> e.id.equals(a))
                        .findFirst()
                        .map(e -> "/slay/looks/" + e.lookId + "/snapshot")
                        .orElse("");
        String imageB =
                entries.stream()
                        .filter(e -> e.id.equals(b))
                        .findFirst()
                        .map(e -> "/slay/looks/" + e.lookId + "/snapshot")
                        .orElse("");
        // Alternate sides by server ballot ID to avoid a persistent left-side advantage.
        return id.getLeastSignificantBits() % 2 == 0
                ? new Ballot(id, catalog.theme(c.currentTheme()).title(), a, b, imageA, imageB)
                : new Ballot(id, catalog.theme(c.currentTheme()).title(), b, a, imageB, imageA);
    }

    public Mono<Void> vote(UUID user, UUID ballotId, String choice) {
        return verified(user)
                .then(
                        db.sql(
                                        "SELECT competition_id FROM slay_ballots WHERE id=:id AND"
                                                + " voter_id=:u")
                                .bind("id", ballotId)
                                .bind("u", user)
                                .map(r -> r.get("competition_id", UUID.class))
                                .one()
                                .switchIfEmpty(
                                        Mono.error(ApiExceptions.notFound("Ballot not found")))
                                .flatMap(
                                        id ->
                                                mutate(
                                                        id,
                                                        c -> {
                                                            check(
                                                                    c.status.equals("voting")
                                                                            && Instant.now()
                                                                                    .isBefore(
                                                                                            c.deadline),
                                                                    "Voting has closed");
                                                            return db.sql(
                                                                            "UPDATE slay_ballots"
                                                                                + " SET chosen=:pick,answered_at=now()"
                                                                                + " WHERE id=:id"
                                                                                + " AND voter_id=:u"
                                                                                + " AND chosen IS"
                                                                                + " NULL AND"
                                                                                + " round=:r AND"
                                                                                + " :pick"
                                                                                + " IN(entry_a,entry_b)"
                                                                                + " AND served_at<=now()-interval"
                                                                                + " '1 second'"
                                                                                + " RETURNING"
                                                                                + " entry_a,entry_b")
                                                                    .bind("pick", choice)
                                                                    .bind("id", ballotId)
                                                                    .bind("u", user)
                                                                    .bind("r", c.round)
                                                                    .fetch()
                                                                    .one()
                                                                    .switchIfEmpty(
                                                                            Mono.error(
                                                                                    ApiExceptions
                                                                                            .conflict(
                                                                                                    "Vote is"
                                                                                                        + " invalid"
                                                                                                        + " or already"
                                                                                                        + " recorded")))
                                                                    .map(
                                                                            b -> {
                                                                                c.comparisons.add(
                                                                                        new Comparison(
                                                                                                b.get(
                                                                                                                "entry_a")
                                                                                                        .toString(),
                                                                                                b.get(
                                                                                                                "entry_b")
                                                                                                        .toString(),
                                                                                                choice));
                                                                                c.voters.add(
                                                                                        user
                                                                                                .toString());
                                                                                return c;
                                                                            });
                                                        }))
                                .then());
    }

    private Mono<Void> settle(SlayCompetition c) {
        if (!Set.of("results", "cancelled").contains(c.status)) return Mono.empty();
        return db.sql(
                        "UPDATE slay_competitions SET settled=true WHERE id=:id AND NOT settled"
                                + " RETURNING id")
                .bind("id", UUID.fromString(c.id))
                .fetch()
                .one()
                .flatMap(
                        row -> {
                            Mono<Void> room =
                                    c.roomId == null
                                            ? Mono.empty()
                                            : db.sql(
                                                            "UPDATE rooms SET"
                                                                + " status='ended',ranked=:ranked"
                                                                + " WHERE id=:r")
                                                    .bind("r", UUID.fromString(c.roomId))
                                                    .bind("ranked", rated(c))
                                                    .fetch()
                                                    .rowsUpdated()
                                                    .then(
                                                            db.sql(
                                                                            "UPDATE game_sessions"
                                                                                + " SET phase='Results',ended_at=now()"
                                                                                + " WHERE id=:id")
                                                                    .bind(
                                                                            "id",
                                                                            UUID.fromString(c.id))
                                                                    .fetch()
                                                                    .rowsUpdated())
                                                    .then();
                            if (c.status.equals("cancelled"))
                                return room.then(
                                        c.roomId == null
                                                ? Mono.empty()
                                                : championships
                                                        .getObject()
                                                        .stylingNoShow(UUID.fromString(c.roomId)));
                            Map<String, SlayCompetition.Entry> latest = new LinkedHashMap<>();
                            c.entries.forEach(e -> latest.put(e.userId, e));
                            List<SlayCompetition.Entry> entries =
                                    latest.values().stream()
                                            .sorted(Comparator.comparing(e -> e.userId))
                                            .toList();
                            Map<String, String> outcomes = new LinkedHashMap<>();
                            c.contestants()
                                    .forEach(
                                            m -> {
                                                var e = latest.get(m.userId());
                                                outcomes.put(
                                                        m.userId(),
                                                        "rank:"
                                                                + (e == null || e.placement == 0
                                                                        ? c.contestants().size()
                                                                        : e.placement));
                                            });
                            boolean battleDraw =
                                    c.mode.equals("battle")
                                            && entries.size() == 2
                                            && entries.stream().allMatch(e -> e.placement == 1);
                            if (battleDraw) outcomes.replaceAll((user, outcome) -> "tied");
                            Mono<Void> competitive =
                                    c.roomId == null
                                            ? Mono.empty()
                                            : ratings.recordMatch(
                                                    new RatingService.FinishedGame(
                                                            UUID.fromString(c.id),
                                                            UUID.fromString(c.roomId),
                                                            "slayhuud",
                                                            "style",
                                                            outcomes,
                                                            outcomes.keySet()));
                            Map<String, String> bracketOutcome = new LinkedHashMap<>();
                            outcomes.forEach(
                                    (user, outcome) ->
                                            bracketOutcome.put(
                                                    user,
                                                    outcome.equals("rank:1") ? "won" : "lost"));
                            long firstPlaces =
                                    entries.stream().filter(e -> e.placement == 1).count();
                            if (firstPlaces > 1)
                                bracketOutcome.replaceAll((user, outcome) -> "tied");
                            Mono<Void> bracket =
                                    c.roomId == null
                                            ? Mono.empty()
                                            : championships
                                                    .getObject()
                                                    .gameFinished(
                                                            UUID.fromString(c.roomId),
                                                            UUID.fromString(c.id),
                                                            bracketOutcome);
                            Mono<Void> storedResult =
                                    c.roomId == null
                                            ? Mono.empty()
                                            : db.sql(
                                                            "INSERT INTO"
                                                                + " game_results(game_session_id,winning_side,per_player_outcome)"
                                                                + " VALUES(:id,'style',:outcome) ON"
                                                                + " CONFLICT DO NOTHING")
                                                    .bind("id", UUID.fromString(c.id))
                                                    .bind("outcome", Json.of(write(bracketOutcome)))
                                                    .fetch()
                                                    .rowsUpdated()
                                                    .then();
                            return room.then(storedResult)
                                    .then(
                                            Flux.fromIterable(entries)
                                                    .concatMap(
                                                            e ->
                                                                    claim(
                                                                                    UUID.fromString(
                                                                                            e.userId),
                                                                                    "competition:"
                                                                                            + c.id)
                                                                            .flatMap(
                                                                                    fresh -> {
                                                                                        if (!fresh)
                                                                                            return Mono
                                                                                                    .empty();
                                                                                        long
                                                                                                reward =
                                                                                                        battleDraw
                                                                                                                ? 30
                                                                                                                : e.placement
                                                                                                                                == 1
                                                                                                                        ? 100
                                                                                                                        : e.placement
                                                                                                                                        == 2
                                                                                                                                ? 60
                                                                                                                                : e.placement
                                                                                                                                                == 3
                                                                                                                                        ? 30
                                                                                                                                        : 10;
                                                                                        return db.sql(
                                                                                                        "SELECT"
                                                                                                            + " count(*)"
                                                                                                            + " AS n"
                                                                                                            + " FROM"
                                                                                                            + " slay_reward_claims"
                                                                                                            + " WHERE"
                                                                                                            + " user_id=:u"
                                                                                                            + " AND ref"
                                                                                                            + " LIKE"
                                                                                                            + " 'competition:%'"
                                                                                                            + " AND claimed_at>now()-interval"
                                                                                                            + " '24 hours'")
                                                                                                .bind(
                                                                                                        "u",
                                                                                                        UUID
                                                                                                                .fromString(
                                                                                                                        e.userId))
                                                                                                .map(
                                                                                                        r ->
                                                                                                                r
                                                                                                                        .get(
                                                                                                                                "n",
                                                                                                                                Long
                                                                                                                                        .class))
                                                                                                .one()
                                                                                                .flatMap(
                                                                                                        n ->
                                                                                                                n
                                                                                                                                <= 10
                                                                                                                        ? coins.credit(
                                                                                                                                        UUID
                                                                                                                                                .fromString(
                                                                                                                                                        e.userId),
                                                                                                                                        reward,
                                                                                                                                        "slay_placement",
                                                                                                                                        UUID
                                                                                                                                                .fromString(
                                                                                                                                                        c.id))
                                                                                                                                .then(
                                                                                                                                        xp(
                                                                                                                                                UUID
                                                                                                                                                        .fromString(
                                                                                                                                                                e.userId),
                                                                                                                                                e.placement
                                                                                                                                                                == 1
                                                                                                                                                        ? 100
                                                                                                                                                        : 30))
                                                                                                                        : Mono
                                                                                                                                .empty());
                                                                                    }))
                                                    .then())
                                    .then(bracket)
                                    .then(competitive)
                                    .then(
                                            Flux.fromIterable(entries)
                                                    .concatMap(
                                                            e ->
                                                                    awardStyleAchievements(
                                                                            UUID.fromString(
                                                                                    e.userId),
                                                                            c,
                                                                            e))
                                                    .then())
                                    .doOnSuccess(
                                            v ->
                                                    notifications.sendToUsers(
                                                            entries.stream()
                                                                    .map(
                                                                            e ->
                                                                                    UUID.fromString(
                                                                                            e.userId))
                                                                    .toList(),
                                                            "Your SlayHuud results are in",
                                                            catalog.theme(c.currentTheme()).title()
                                                                    + " has a winner.",
                                                            Map.of(
                                                                    "type",
                                                                    "slay_result",
                                                                    "competitionId",
                                                                    c.id)));
                        })
                .then();
    }

    private Mono<Void> awardStyleAchievements(
            UUID user, SlayCompetition c, SlayCompetition.Entry entry) {
        Mono<Long> wins =
                db.sql(
                                "SELECT count(*) AS n FROM match_participants p JOIN match_records"
                                        + " m ON m.id=p.match_id WHERE p.user_id=:u AND"
                                        + " m.game_type='slayhuud' AND p.outcome='won'")
                        .bind("u", user)
                        .map(r -> r.get("n", Long.class))
                        .one();
        Mono<Boolean> champion =
                db.sql("SELECT id FROM championships WHERE champion_id=:u AND game_type='slayhuud'")
                        .bind("u", user)
                        .fetch()
                        .first()
                        .hasElement();
        return Mono.zip(wins, champion)
                .flatMap(
                        t -> {
                            List<app.truearena.api.competitive.AchievementType> awards =
                                    new ArrayList<>();
                            if (t.getT1() >= 5)
                                awards.add(
                                        app.truearena.api.competitive.AchievementType
                                                .SLAY_FIVE_WINS);
                            if (entry.placement <= 3
                                    && entry.placement > 0
                                    && c.contestants().size() >= 4)
                                awards.add(
                                        app.truearena.api.competitive.AchievementType
                                                .SLAY_TOP_THREE);
                            if (t.getT2())
                                awards.add(
                                        app.truearena.api.competitive.AchievementType
                                                .SLAY_CHAMPION);
                            return Flux.fromIterable(awards)
                                    .concatMap(
                                            a ->
                                                    db.sql(
                                                                    "INSERT INTO"
                                                                        + " player_achievements(user_id,type,game_type,metadata,display_priority,rarity)"
                                                                        + " VALUES(:u,:t,'slayhuud',:m,:p,:r)"
                                                                        + " ON CONFLICT DO NOTHING")
                                                            .bind("u", user)
                                                            .bind("t", a.name())
                                                            .bind(
                                                                    "m",
                                                                    Json.of(
                                                                            "{\"competitionId\":\""
                                                                                    + c.id
                                                                                    + "\"}"))
                                                            .bind("p", a.displayPriority())
                                                            .bind("r", a.rarity())
                                                            .fetch()
                                                            .rowsUpdated()
                                                            .then(
                                                                    a
                                                                                            == app
                                                                                                    .truearena
                                                                                                    .api
                                                                                                    .competitive
                                                                                                    .AchievementType
                                                                                                    .SLAY_FIVE_WINS
                                                                                    || a
                                                                                            == app
                                                                                                    .truearena
                                                                                                    .api
                                                                                                    .competitive
                                                                                                    .AchievementType
                                                                                                    .SLAY_CHAMPION
                                                                            ? Flux.fromIterable(
                                                                                            List.of(
                                                                                                    "female",
                                                                                                    "male"))
                                                                                    .concatMap(
                                                                                            body ->
                                                                                                    db.sql(
                                                                                                                    "INSERT"
                                                                                                                        + " INTO"
                                                                                                                        + " slay_wardrobe(user_id,item_id,source)"
                                                                                                                        + " VALUES(:u,:i,'achievement')"
                                                                                                                        + " ON CONFLICT"
                                                                                                                        + " DO NOTHING")
                                                                                                            .bind(
                                                                                                                    "u",
                                                                                                                    user)
                                                                                                            .bind(
                                                                                                                    "i",
                                                                                                                    body
                                                                                                                            + (a
                                                                                                                                            == app
                                                                                                                                                    .truearena
                                                                                                                                                    .api
                                                                                                                                                    .competitive
                                                                                                                                                    .AchievementType
                                                                                                                                                    .SLAY_CHAMPION
                                                                                                                                    ? "-champion"
                                                                                                                                    : "-winner"))
                                                                                                            .fetch()
                                                                                                            .rowsUpdated())
                                                                                    .then()
                                                                            : Mono.empty()))
                                    .then();
                        });
    }

    public Flux<Map<String, Object>> list(UUID user) {
        return db.sql(
                        "SELECT state FROM slay_competitions WHERE status"
                            + " IN('lobby','styling','voting','round_result') OR state->'members'"
                            + " @> :member ORDER BY created_at DESC LIMIT 60")
                .bind("member", Json.of("[{\"userId\":\"" + user + "\"}]"))
                .map(r -> read(r.get("state", Json.class).asString(), SlayCompetition.class))
                .all()
                .concatMap(
                        c -> allowed(user, c).flatMapMany(ok -> ok ? view(user, c) : Flux.empty()));
    }

    private Mono<Boolean> allowed(UUID viewer, SlayCompetition c) {
        return c.roomId == null
                ? Mono.just(true)
                : championships.getObject().spectatorAllowed(UUID.fromString(c.roomId), viewer);
    }

    private Mono<Map<String, Object>> view(UUID viewer, SlayCompetition c) {
        return allowed(viewer, c)
                .flatMap(
                        ok ->
                                ok
                                        ? viewAllowed(viewer, c)
                                        : Mono.error(
                                                ApiExceptions.forbidden(
                                                        "Private championship match")));
    }

    private Mono<Map<String, Object>> viewAllowed(UUID viewer, SlayCompetition c) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("id", c.id);
        result.put("roomId", c.roomId);
        result.put("mode", c.mode);
        result.put("status", c.status);
        result.put("theme", catalog.theme(c.currentTheme()));
        result.put("round", c.round);
        result.put("deadline", c.deadline);
        result.put("serverTime", Instant.now());
        result.put("seats", c.seats);
        result.put("contestants", c.contestants().size());
        result.put("judges", c.judges().size());
        result.put("contestantBody", c.contestantBody);
        result.put("host", viewer.toString().equals(c.hostId));
        result.put("developmentAssets", catalog.manifest().developmentAssets());
        result.put("rated", rated(c));
        result.put("voteCount", c.comparisons.size());
        result.put("communityUsed", c.communityUsed);
        var member =
                c.members.stream()
                        .filter(m -> m.userId().equals(viewer.toString()))
                        .findFirst()
                        .orElse(null);
        result.put("role", member == null ? "spectator" : member.role());
        result.put("body", member == null ? null : member.body());
        result.put("eliminated", c.eliminated.contains(viewer.toString()));
        result.put(
                "finalRound",
                c.isElimination() && c.currentEntries().size() == 2 && c.status.equals("voting"));
        result.put(
                "judged",
                c.judgements.containsKey(c.round + ":final:" + viewer)
                        || (c.revealed() != null
                                && c.judgements.containsKey(
                                        c.round + ":" + c.revealed().id + ":" + viewer)));
        result.put(
                "draw",
                c.mode.equals("battle")
                        && c.status.equals("results")
                        && c.currentEntries().size() == 2
                        && c.currentEntries().stream().allMatch(e -> e.placement == 1));
        result.put(
                "submitted",
                c.currentEntries().stream().anyMatch(e -> e.userId.equals(viewer.toString())));
        List<SlayCompetition.Entry> visible = new ArrayList<>();
        if (c.status.equals("results")) {
            Map<String, SlayCompetition.Entry> latest = new LinkedHashMap<>();
            c.entries.forEach(e -> latest.put(e.userId, e));
            visible.addAll(latest.values());
            visible.sort(Comparator.comparingInt(e -> e.placement));
        } else if (c.status.equals("round_result")) visible.addAll(c.currentEntries());
        else if (c.isElimination() && c.status.equals("voting") && c.currentEntries().size() == 2)
            visible.addAll(c.currentEntries());
        else if (c.isElimination() && c.status.equals("voting") && c.revealed() != null)
            visible.add(c.revealed());
        else
            visible.addAll(
                    c.currentEntries().stream()
                            .filter(e -> e.userId.equals(viewer.toString()))
                            .toList());
        result.put("resultCount", visible.size());
        if (c.isAsync() && c.status.equals("results") && visible.size() > 100) {
            var mine =
                    visible.stream()
                            .filter(e -> e.userId.equals(viewer.toString()))
                            .findFirst()
                            .orElse(null);
            visible = new ArrayList<>(visible.subList(0, 100));
            if (mine != null && !visible.contains(mine)) visible.add(mine);
        }
        return Flux.fromIterable(visible)
                .concatMap(
                        e -> {
                            Map<String, Object> entry = new LinkedHashMap<>();
                            entry.put("id", e.id);
                            entry.put("image", "/slay/looks/" + e.lookId + "/snapshot");
                            entry.put("mine", e.userId.equals(viewer.toString()));
                            entry.put("lookId", e.lookId);
                            if (c.status.equals("results") || c.status.equals("round_result")) {
                                entry.put("system", e.system);
                                entry.put("community", e.community);
                                entry.put("score", e.finalScore);
                                entry.put("placement", e.placement);
                            }
                            if (c.status.equals("results"))
                                return users.findById(UUID.fromString(e.userId))
                                        .map(
                                                u -> {
                                                    entry.put("username", u.username());
                                                    entry.put("userId", u.id());
                                                    return entry;
                                                })
                                        .defaultIfEmpty(entry);
                            return Mono.just(entry);
                        })
                .collectList()
                .map(
                        entries -> {
                            result.put("entries", entries);
                            return result;
                        })
                .flatMap(
                        data ->
                                c.roomId == null
                                        ? Mono.just(data)
                                        : db.sql("SELECT code FROM rooms WHERE id=:r")
                                                .bind("r", UUID.fromString(c.roomId))
                                                .map(r -> r.get("code", String.class))
                                                .one()
                                                .map(
                                                        code -> {
                                                            data.put("roomCode", code);
                                                            return data;
                                                        })
                                                .defaultIfEmpty(data));
    }

    public Mono<Void> block(UUID user, UUID other) {
        check(!user.equals(other), "You cannot block yourself");
        return db.sql(
                        "INSERT INTO user_blocks(blocker_id,blocked_id) VALUES(:u,:b) ON CONFLICT"
                                + " DO NOTHING")
                .bind("u", user)
                .bind("b", other)
                .fetch()
                .rowsUpdated()
                .then();
    }

    public Mono<Void> report(UUID user, UUID look, String reason) {
        check(
                reason != null && !reason.isBlank() && reason.length() <= 500,
                "Provide a short report reason");
        return db.sql(
                        "INSERT INTO content_reports(reporter_id,subject_type,subject_id,reason)"
                                + " SELECT :u,'slay_look',id,:reason FROM slay_looks WHERE id=:id")
                .bind("u", user)
                .bind("reason", reason)
                .bind("id", look)
                .fetch()
                .rowsUpdated()
                .flatMap(
                        n ->
                                n == 1
                                        ? Mono.empty()
                                        : Mono.error(ApiExceptions.notFound("Look not found")));
    }

    public Mono<Void> tick() {
        return db.sql(
                        "SELECT id FROM slay_competitions WHERE deadline<=now() ORDER BY deadline"
                                + " LIMIT 100")
                .map(r -> r.get("id", UUID.class))
                .all()
                .concatMap(id -> mutate(id, Mono::just))
                .then();
    }

    public Mono<Void> ensureScheduled() {
        return Flux.fromIterable(List.of("daily", "weekly"))
                .concatMap(
                        mode -> {
                            LocalDate day = LocalDate.now(ZoneOffset.UTC);
                            if (mode.equals("weekly"))
                                day =
                                        day.with(
                                                java.time.temporal.TemporalAdjusters.previousOrSame(
                                                        DayOfWeek.MONDAY));
                            UUID id =
                                    UUID.nameUUIDFromBytes(
                                            ("slay:" + mode + ":" + day)
                                                    .getBytes(
                                                            java.nio.charset.StandardCharsets
                                                                    .UTF_8));
                            SlayCompetition c = new SlayCompetition();
                            c.id = id.toString();
                            c.mode = mode;
                            c.themeId =
                                    catalog.manifest()
                                            .themes()
                                            .get(
                                                    Math.floorMod(
                                                            day.toEpochDay(),
                                                            catalog.manifest().themes().size()))
                                            .id();
                            c.status = "styling";
                            c.seats = 5000;
                            c.startedAt = day.atStartOfDay().toInstant(ZoneOffset.UTC);
                            c.deadline =
                                    day.plusDays(mode.equals("daily") ? 1 : 7)
                                            .atStartOfDay()
                                            .toInstant(ZoneOffset.UTC);
                            c.votingSeconds = mode.equals("daily") ? 86400 : 172800;
                            return insert(c).then();
                        })
                .then();
    }
}
