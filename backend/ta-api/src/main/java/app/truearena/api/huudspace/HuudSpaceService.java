package app.truearena.api.huudspace;

import app.truearena.api.huudspace.HuudSpaceDtos.CurrentGame;
import app.truearena.api.huudspace.HuudSpaceDtos.HistoryHuud;
import app.truearena.api.huudspace.HuudSpaceDtos.HuudSpaceView;
import app.truearena.api.huudspace.HuudSpaceDtos.LiveHuud;
import app.truearena.api.huudspace.HuudSpaceDtos.Person;
import app.truearena.api.calls.VoiceSessionService;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.room.RoomService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.UserRepository;
import app.truearena.voice.LiveKitRoomAdmin;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.ReactiveTransactionManager;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Huud spaces — the persistent place people hang out and play one game after
 * another. A game is a room linked to the space; when it ends the space and
 * everyone in it stay.
 *
 * <p>Membership is durable and separate from any screen or socket: the app
 * heartbeats every Huud you're in while it's open. A host who leaves, or whose
 * app goes quiet for {@code huud.host-grace}, hands the Huud to whoever joined
 * next (guests can't host, and nobody can own two live Huuds). Members quiet
 * for {@code huud.member-timeout} are marked as gone, and a Huud with nobody
 * left in it ends.
 */
@Service
public class HuudSpaceService {

    /** No 0/O, 1/I/L: a code a child can read out loud without a mix-up. */
    static final String CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    static final int CODE_LENGTH = 6;
    /** Seen this recently = shown as "here" with a green dot. */
    static final Duration HERE_WINDOW = Duration.ofMinutes(2);
    static final int LIST_LIMIT = 40;

    private static final SecureRandom RANDOM = new SecureRandom();

    private final DatabaseClient db;
    private final TransactionalOperator tx;
    private final InboxRegistry inbox;
    private final RoomService rooms;
    private final UserRepository users;
    private final VoiceSessionService voiceSessions;
    private final LiveKitRoomAdmin voice;
    private final Duration hostGrace;
    private final Duration memberTimeout;

    public HuudSpaceService(DatabaseClient db, ReactiveTransactionManager manager, InboxRegistry inbox,
                            RoomService rooms, UserRepository users, VoiceSessionService voiceSessions,
                            LiveKitRoomAdmin voice,
                            @Value("${huud.host-grace:PT5M}") Duration hostGrace,
                            @Value("${huud.member-timeout:PT10M}") Duration memberTimeout) {
        this.db = db;
        this.tx = TransactionalOperator.create(manager);
        this.inbox = inbox;
        this.rooms = rooms;
        this.users = users;
        this.voiceSessions = voiceSessions;
        this.voice = voice;
        this.hostGrace = hostGrace;
        this.memberTimeout = memberTimeout;
    }

    record Space(UUID id, String code, String name, String privacy, UUID ownerId, UUID createdBy,
                 String status, UUID currentRoomId, Instant createdAt, Instant endedAt) {
        boolean active() {
            return "active".equals(status);
        }
    }

    record Membership(Instant leftAt, boolean removed) {
        boolean in() {
            return leftAt == null && !removed;
        }
    }

    // ------------------------------------------------------------ create / open

    /**
     * Makes a Huud, or reopens the one you already host — one live Huud per
     * host, so tapping Create twice never makes two.
     */
    public Mono<HuudSpaceView> create(UUID user, String requestedName, String requestedPrivacy) {
        String privacy = privacyOrDefault(requestedPrivacy);
        return users.findById(user)
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("unknown user")))
                .flatMap(me -> {
                    if (me.isGuest()) {
                        return Mono.error(ApiExceptions.forbidden(
                                "Verify your phone or email to make a Huud — you can still join friends' Huuds"));
                    }
                    String name = nameOrDefault(requestedName, me.displayName());
                    return tx.transactional(lock("huud-space-owner:" + user)
                            .then(ownedId(user))
                            .switchIfEmpty(Mono.defer(() -> freshCode().flatMap(code -> db.sql(
                                            "INSERT INTO huud_spaces(code,name,privacy,owner_id,created_by) "
                                                    + "VALUES(:code,:name,:privacy,:user,:user) RETURNING id")
                                    .bind("code", code).bind("name", name).bind("privacy", privacy).bind("user", user)
                                    .map((r, m) -> r.get("id", UUID.class)).one())))
                            .flatMap(id -> admitRow(id, user).thenReturn(id)));
                })
                .flatMap(id -> view(id, user));
    }

    /** The Huud you host right now, if any. */
    public Mono<HuudSpaceView> current(UUID user) {
        return ownedId(user).flatMap(id -> view(id, user));
    }

    private Mono<UUID> ownedId(UUID user) {
        return db.sql("SELECT id FROM huud_spaces WHERE owner_id=:user AND status='active'")
                .bind("user", user).map((r, m) -> r.get("id", UUID.class)).one();
    }

    private Mono<String> freshCode() {
        return Mono.fromSupplier(HuudSpaceService::randomCode)
                .flatMap(code -> db.sql("SELECT EXISTS(SELECT 1 FROM huud_spaces WHERE code=:code AND status='active') AS taken")
                        .bind("code", code).map((r, m) -> Boolean.TRUE.equals(r.get("taken", Boolean.class))).one()
                        .flatMap(taken -> taken ? Mono.empty() : Mono.just(code)))
                .repeatWhenEmpty(5, attempts -> attempts)
                .switchIfEmpty(Mono.error(ApiExceptions.conflict("couldn't make a Huud code — try again")));
    }

    static String randomCode() {
        var code = new StringBuilder(CODE_LENGTH);
        for (int i = 0; i < CODE_LENGTH; i++) {
            code.append(CODE_ALPHABET.charAt(RANDOM.nextInt(CODE_ALPHABET.length())));
        }
        return code.toString();
    }

    static String privacyOrDefault(String requested) {
        if (requested == null || requested.isBlank()) return "friends";
        String privacy = requested.trim().toLowerCase();
        if (!HuudSpaceDtos.PRIVACY.contains(privacy)) {
            throw ApiExceptions.badRequest("privacy must be friends, private or public");
        }
        return privacy;
    }

    static String nameOrDefault(String requested, String displayName) {
        String name = requested == null ? "" : requested.strip().replaceAll("\\s+", " ");
        if (name.isEmpty()) {
            String first = displayName == null || displayName.isBlank() ? "My" : displayName.strip().split("\\s+")[0];
            name = first.endsWith("s") ? first + "' Huud" : first + "'s Huud";
        }
        return name.length() > 40 ? name.substring(0, 40).strip() : name;
    }

    // ------------------------------------------------------------ joining

    public Mono<HuudSpaceView> joinByCode(UUID user, String code) {
        String normalized = code == null ? "" : code.trim().toUpperCase();
        return db.sql("SELECT id FROM huud_spaces WHERE code=:code AND status='active'")
                .bind("code", normalized).map((r, m) -> r.get("id", UUID.class)).one()
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("No Huud has that code — check it and try again")))
                // The code is the invitation: it works whatever the privacy.
                .flatMap(id -> admit(id, user, true));
    }

    /** Joining from the Live tab, without a code. */
    public Mono<HuudSpaceView> join(UUID user, UUID id) {
        return admit(id, user, false);
    }

    private Mono<HuudSpaceView> admit(UUID id, UUID user, boolean withCode) {
        return space(id).filter(Space::active)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("This Huud has ended")))
                .flatMap(s -> membership(id, user).map(Optional::of).defaultIfEmpty(Optional.empty())
                        .flatMap(m -> {
                            if (m.isPresent() && m.get().removed()) {
                                return Mono.error(ApiExceptions.forbidden("You can't join this Huud"));
                            }
                            Mono<Boolean> allowed = withCode || m.isPresent() ? Mono.just(true) : canSee(s, user);
                            return allowed.flatMap(ok -> ok
                                    ? tx.transactional(lock("huud-space:" + id).then(admitRow(id, user)))
                                        .doOnSuccess(v -> { if (m.isEmpty() || !m.get().in()) notifyMembers(id, "joined", user); })
                                        .then(view(id, user))
                                    : Mono.error(ApiExceptions.forbidden("This Huud is just for the host's friends — ask for the code")));
                        }));
    }

    /** Back in (or in for the first time). Someone returning after leaving goes to the end of the host line. */
    private Mono<Void> admitRow(UUID id, UUID user) {
        return db.sql("INSERT INTO huud_space_members(huud_space_id,user_id) VALUES(:id,:user) "
                        + "ON CONFLICT(huud_space_id,user_id) DO UPDATE SET "
                        + "joined_at=CASE WHEN huud_space_members.left_at IS NULL THEN huud_space_members.joined_at ELSE now() END, "
                        + "left_at=NULL, last_seen_at=now() WHERE NOT huud_space_members.removed")
                .bind("id", id).bind("user", user).fetch().rowsUpdated().then();
    }

    private Mono<Boolean> canSee(Space s, UUID user) {
        if (s.ownerId().equals(user) || "public".equals(s.privacy())) return Mono.just(true);
        if (!"friends".equals(s.privacy())) return Mono.just(false);
        return friends(user, s.ownerId());
    }

    private Mono<Boolean> friends(UUID a, UUID b) {
        return db.sql("SELECT EXISTS(SELECT 1 FROM friends WHERE status='accepted' "
                        + "AND low_user_id=LEAST(:a,:b) AND high_user_id=GREATEST(:a,:b)) AS ok")
                .bind("a", a).bind("b", b).map((r, m) -> Boolean.TRUE.equals(r.get("ok", Boolean.class))).one();
    }

    // ------------------------------------------------------------ leaving / ending

    /** Leave for good (navigating away is not leaving). A leaving host hands the Huud on. */
    public Mono<Void> leave(UUID user, UUID id) {
        return tx.transactional(lock("huud-space:" + id)
                        .then(space(id))
                        .filter(Space::active)
                        .flatMap(s -> db.sql("UPDATE huud_space_members SET left_at=now() "
                                        + "WHERE huud_space_id=:id AND user_id=:user AND left_at IS NULL")
                                .bind("id", id).bind("user", user).fetch().rowsUpdated()
                                .flatMap(n -> n == 0 ? Mono.<String>empty()
                                        : s.ownerId().equals(user) ? handOff(id).map(next -> "host").defaultIfEmpty("end")
                                        : Mono.just("left"))))
                .flatMap(outcome -> switch (outcome) {
                    case "end" -> finish(id, user);
                    case "host" -> Mono.fromRunnable(() -> notifyMembers(id, "host", user));
                    default -> Mono.fromRunnable(() -> notifyMembers(id, "left", user));
                })
                .then();
    }

    /** Host only: closes the Huud for everyone and retires its code. */
    public Mono<Void> end(UUID user, UUID id) {
        return requireHost(id, user).flatMap(s -> cancelWaitingGame(s, user)).then(finish(id, user));
    }

    private Mono<Void> finish(UUID id, UUID by) {
        return members(id, false).collectList().flatMap(people -> tx.transactional(
                        db.sql("UPDATE huud_spaces SET status='ended',ended_at=now(),current_room_id=NULL "
                                        + "WHERE id=:id AND status='active'")
                                .bind("id", id).fetch().rowsUpdated()
                                .then(db.sql("UPDATE huud_space_members SET left_at=now() "
                                                + "WHERE huud_space_id=:id AND left_at IS NULL")
                                        .bind("id", id).fetch().rowsUpdated()))
                .doOnSuccess(n -> people.forEach(p -> notify(p.userId(), id, "ended", by)))
                .then(Flux.fromIterable(people).concatMap(p -> dropFromVoice(id, p.userId())).then()));
    }

    /** Host only: takes someone out of the Huud; they can't come back into this one. */
    public Mono<Void> remove(UUID host, UUID id, UUID target) {
        if (host.equals(target)) return Mono.error(ApiExceptions.badRequest("to go, tap Leave"));
        return requireHost(id, host).flatMap(s -> db.sql("UPDATE huud_space_members SET left_at=now(),removed=true "
                                + "WHERE huud_space_id=:id AND user_id=:target")
                        .bind("id", id).bind("target", target).fetch().rowsUpdated())
                .doOnSuccess(n -> {
                    notify(target, id, "removed", host);
                    notifyMembers(id, "left", target);
                })
                .then(dropFromVoice(id, target));
    }

    public Mono<HuudSpaceView> update(UUID host, UUID id, String name, String privacy) {
        return requireHost(id, host).flatMap(s -> {
            String nextPrivacy = privacy == null ? s.privacy() : privacyOrDefault(privacy);
            String nextName = name == null ? s.name() : nameOrDefault(name, s.name());
            return db.sql("UPDATE huud_spaces SET name=:name,privacy=:privacy WHERE id=:id")
                    .bind("name", nextName).bind("privacy", nextPrivacy).bind("id", id).fetch().rowsUpdated();
        }).doOnSuccess(n -> notifyMembers(id, "updated", host)).then(view(id, host));
    }

    /**
     * Hands the Huud to the person who joined next and is still here. Guests
     * can't host, and someone who already hosts a live Huud is skipped. Empty
     * when nobody can take over.
     */
    Mono<UUID> handOff(UUID id) {
        return db.sql("UPDATE huud_spaces s SET owner_id=next.user_id FROM ("
                        + "SELECT m.user_id FROM huud_space_members m JOIN users u ON u.id=m.user_id "
                        + "WHERE m.huud_space_id=:id AND m.left_at IS NULL AND NOT m.removed AND NOT u.is_guest "
                        + "AND m.user_id <> (SELECT owner_id FROM huud_spaces WHERE id=:id) "
                        + "AND NOT EXISTS(SELECT 1 FROM huud_spaces o WHERE o.owner_id=m.user_id AND o.status='active') "
                        + "ORDER BY m.joined_at, m.user_id LIMIT 1) next "
                        + "WHERE s.id=:id AND s.status='active' RETURNING s.owner_id")
                .bind("id", id).map((r, m) -> r.get("owner_id", UUID.class)).one();
    }

    // ------------------------------------------------------------ presence

    /** The app calls this while it's open, for every Huud you're in. */
    public Mono<Void> heartbeat(UUID user) {
        return db.sql("UPDATE huud_space_members m SET last_seen_at=now() FROM huud_spaces s "
                        + "WHERE s.id=m.huud_space_id AND s.status='active' AND m.user_id=:user AND m.left_at IS NULL")
                .bind("user", user).fetch().rowsUpdated().then();
    }

    /** Scheduled: drop the long-gone, hand on Huuds whose host vanished, end empty Huuds. */
    public Mono<Void> expire() {
        var touched = new java.util.HashSet<UUID>();
        return db.sql("UPDATE huud_space_members SET left_at=now() WHERE left_at IS NULL "
                        + "AND last_seen_at < now() - make_interval(secs => :secs) RETURNING huud_space_id, user_id")
                .bind("secs", (double) memberTimeout.toSeconds())
                .map((r, m) -> Map.entry(r.get("huud_space_id", UUID.class), r.get("user_id", UUID.class))).all()
                .doOnNext(gone -> {
                    touched.add(gone.getKey());
                    notifyMembers(gone.getKey(), "left", gone.getValue());
                })
                .then(db.sql("SELECT s.id, s.owner_id FROM huud_spaces s WHERE s.status='active' AND NOT EXISTS("
                                + "SELECT 1 FROM huud_space_members m WHERE m.huud_space_id=s.id AND m.user_id=s.owner_id "
                                + "AND m.left_at IS NULL AND m.last_seen_at > now() - make_interval(secs => :secs))")
                        .bind("secs", (double) hostGrace.toSeconds())
                        .map((r, m) -> Map.entry(r.get("id", UUID.class), r.get("owner_id", UUID.class))).all()
                        .concatMap(absent -> tx.transactional(lock("huud-space:" + absent.getKey()).then(handOff(absent.getKey())))
                                .doOnNext(next -> notifyMembers(absent.getKey(), "host", absent.getValue())))
                        .then())
                .then(db.sql("UPDATE huud_spaces s SET status='ended',ended_at=now(),current_room_id=NULL "
                                + "WHERE s.status='active' AND NOT EXISTS(SELECT 1 FROM huud_space_members m "
                                + "WHERE m.huud_space_id=s.id AND m.left_at IS NULL)")
                        .fetch().rowsUpdated())
                .then();
    }

    // ------------------------------------------------------------ games

    /**
     * Host only: start setting up a game in the Huud. One game at a time — a
     * game that's waiting or being played has to finish (or be put away) first.
     */
    public Mono<RoomView> addGame(UUID host, UUID id, String gameType) {
        return requireHost(id, host)
                .flatMap(s -> currentGame(s.currentRoomId()).flatMap(game -> {
                            if (!"finished".equals(game.status())) {
                                return Mono.error(ApiExceptions.conflict(
                                        "Finish the game that's on first, or put it away"));
                            }
                            return Mono.just(s);
                        }).defaultIfEmpty(s))
                .flatMap(s -> rooms.create(host, null, gameType, null, null, false))
                .flatMap(room -> db.sql("UPDATE rooms SET huud_space_id=:id WHERE id=:room")
                        .bind("id", id).bind("room", room.id()).fetch().rowsUpdated()
                        .then(db.sql("UPDATE huud_spaces SET current_room_id=:room WHERE id=:id")
                                .bind("room", room.id()).bind("id", id).fetch().rowsUpdated())
                        .thenReturn(room))
                .doOnSuccess(room -> notifyMembers(id, "game", host));
    }

    /** Host only: put the current game away so another can be picked. A game in play can't be. */
    public Mono<HuudSpaceView> clearGame(UUID host, UUID id) {
        return requireHost(id, host)
                .flatMap(s -> currentGame(s.currentRoomId())
                        .flatMap(game -> "playing".equals(game.status())
                                ? Mono.error(ApiExceptions.conflict("The game is still being played"))
                                : cancelWaitingGame(s, host))
                        .then(db.sql("UPDATE huud_spaces SET current_room_id=NULL WHERE id=:id")
                                .bind("id", id).fetch().rowsUpdated()))
                .doOnSuccess(n -> notifyMembers(id, "game", host))
                .then(view(id, host));
    }

    /** A game nobody has started yet goes away with its stakes refunded; the room's host must ask. */
    private Mono<Void> cancelWaitingGame(Space s, UUID by) {
        if (s.currentRoomId() == null) return Mono.empty();
        return currentGame(s.currentRoomId())
                .filter(game -> "waiting".equals(game.status()))
                .flatMap(game -> rooms.abandon(game.roomId(), by).onErrorResume(e -> Mono.empty()));
    }

    // ------------------------------------------------------------ reading

    public Mono<HuudSpaceView> view(UUID id, UUID viewer) {
        return space(id)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("That Huud isn't here any more")))
                .flatMap(s -> membership(id, viewer).map(Optional::of).defaultIfEmpty(Optional.empty())
                        .flatMap(m -> {
                            boolean in = m.isPresent() && m.get().in() && s.active();
                            Mono<Boolean> allowed = m.isPresent()
                                    ? Mono.just(!m.get().removed())
                                    : s.active() ? canSee(s, viewer) : Mono.just(false);
                            return allowed.flatMap(ok -> {
                                if (!ok) return Mono.error(ApiExceptions.forbidden("This Huud isn't open to you"));
                                Mono<Void> touch = in ? db.sql("UPDATE huud_space_members SET last_seen_at=now() "
                                                + "WHERE huud_space_id=:id AND user_id=:user")
                                        .bind("id", id).bind("user", viewer).fetch().rowsUpdated().then() : Mono.empty();
                                return touch.then(Mono.zip(
                                        members(id, !s.active()).collectList(),
                                        currentGame(s.currentRoomId()).map(Optional::of).defaultIfEmpty(Optional.empty())))
                                        .map(t -> {
                                            List<Person> people = t.getT1();
                                            Person host = people.stream().filter(Person::host).findFirst()
                                                    .orElse(null);
                                            return new HuudSpaceView(s.id(), in ? s.code() : null, s.name(), s.privacy(),
                                                    s.status(), host, people, t.getT2().orElse(null), in,
                                                    s.ownerId().equals(viewer) && s.active(),
                                                    "huud-" + s.id(), s.createdAt(), s.endedAt());
                                        });
                            });
                        }));
    }

    /** Live Huuds you can look into: yours, your friends' and public ones. */
    public Flux<LiveHuud> live(UUID viewer) {
        return db.sql("SELECT s.id, s.name, s.privacy, s.created_at, r.game_type, r.status AS room_status, "
                        + "EXISTS(SELECT 1 FROM huud_space_members me WHERE me.huud_space_id=s.id AND me.user_id=:user AND me.left_at IS NULL) AS mine, "
                        + "(SELECT count(*) FROM huud_space_members c WHERE c.huud_space_id=s.id AND c.left_at IS NULL) AS present "
                        + "FROM huud_spaces s LEFT JOIN rooms r ON r.id=s.current_room_id "
                        + "WHERE s.status='active' "
                        + "AND NOT EXISTS(SELECT 1 FROM huud_space_members x WHERE x.huud_space_id=s.id AND x.user_id=:user AND x.removed) "
                        + "AND EXISTS(SELECT 1 FROM huud_space_members p WHERE p.huud_space_id=s.id AND p.left_at IS NULL) "
                        + "AND (s.privacy='public' "
                        + "  OR EXISTS(SELECT 1 FROM huud_space_members me WHERE me.huud_space_id=s.id AND me.user_id=:user AND me.left_at IS NULL) "
                        + "  OR (s.privacy='friends' AND EXISTS(SELECT 1 FROM friends f WHERE f.status='accepted' "
                        + "      AND f.low_user_id=LEAST(s.owner_id,:user) AND f.high_user_id=GREATEST(s.owner_id,:user)))) "
                        + "ORDER BY mine DESC, present DESC, s.created_at DESC LIMIT " + LIST_LIMIT)
                .bind("user", viewer)
                .map((r, m) -> new Object[]{r.get("id", UUID.class), r.get("name", String.class),
                        r.get("privacy", String.class), instant(r.get("created_at")), r.get("game_type", String.class),
                        r.get("room_status", String.class), Boolean.TRUE.equals(r.get("mine", Boolean.class)),
                        ((Number) r.get("present")).intValue()})
                .all()
                .concatMap(row -> members((UUID) row[0], false).collectList().map(people -> new LiveHuud(
                        (UUID) row[0], (String) row[1], (String) row[2],
                        people.stream().filter(Person::host).findFirst().orElse(null),
                        (int) row[7], people.stream().limit(6).toList(), (String) row[4],
                        row[5] == null ? null : gameStatus((String) row[5]), (boolean) row[6], (Instant) row[3])));
    }

    /**
     * Every Huud you made or joined, newest first, with who was there and what
     * you played. A finished Huud nobody else came to and nothing was played
     * in is left out — it's an empty room, not a memory.
     */
    public Flux<HistoryHuud> history(UUID viewer) {
        return db.sql("SELECT s.* FROM huud_spaces s JOIN huud_space_members m ON m.huud_space_id=s.id "
                        + "WHERE m.user_id=:user AND NOT m.removed "
                        + "AND (s.status='active' "
                        + "  OR EXISTS(SELECT 1 FROM huud_space_members o WHERE o.huud_space_id=s.id AND o.user_id<>s.created_by AND NOT o.removed) "
                        + "  OR EXISTS(SELECT 1 FROM game_sessions g JOIN rooms r ON r.id=g.room_id WHERE r.huud_space_id=s.id)) "
                        + "ORDER BY (s.status='active') DESC, COALESCE(s.ended_at, s.created_at) DESC LIMIT " + LIST_LIMIT)
                .bind("user", viewer).fetch().all().map(HuudSpaceService::toSpace)
                .concatMap(s -> Mono.zip(members(s.id(), true).collectList(), gamesPlayed(s.id()))
                        .map(t -> new HistoryHuud(s.id(), s.name(), s.privacy(), s.status(),
                                s.createdBy().equals(viewer), s.active() && s.ownerId().equals(viewer),
                                t.getT1().stream().filter(Person::host).findFirst().orElse(null), t.getT1(),
                                new ArrayList<>(t.getT2().keySet()),
                                t.getT2().values().stream().mapToInt(Integer::intValue).sum(),
                                s.createdAt(), s.endedAt())));
    }

    private Mono<Map<String, Integer>> gamesPlayed(UUID id) {
        return db.sql("SELECT g.game_type, count(*) AS n, max(g.started_at) AS last FROM game_sessions g "
                        + "JOIN rooms r ON r.id=g.room_id WHERE r.huud_space_id=:id GROUP BY g.game_type ORDER BY last DESC")
                .bind("id", id)
                .map((r, m) -> Map.entry(r.get("game_type", String.class), ((Number) r.get("n")).intValue()))
                .all()
                .collect(LinkedHashMap::new, (map, e) -> map.put(e.getKey(), e.getValue()));
    }

    /** People in the Huud (or, with {@code everyone}, everyone who ever was), in arrival order. */
    private Flux<Person> members(UUID id, boolean everyone) {
        return db.sql("SELECT m.user_id, m.joined_at, (m.left_at IS NULL AND m.last_seen_at > now() - make_interval(secs => :here)) AS here, "
                        + "(s.owner_id=m.user_id) AS host, u.display_name, u.username, u.avatar_url "
                        + "FROM huud_space_members m JOIN users u ON u.id=m.user_id JOIN huud_spaces s ON s.id=m.huud_space_id "
                        + "WHERE m.huud_space_id=:id AND NOT m.removed AND (:everyone OR m.left_at IS NULL) "
                        + "ORDER BY (s.owner_id=m.user_id) DESC, m.joined_at")
                .bind("id", id).bind("everyone", everyone).bind("here", (double) HERE_WINDOW.toSeconds())
                .map((r, m) -> new Person(r.get("user_id", UUID.class), r.get("display_name", String.class),
                        r.get("username", String.class), r.get("avatar_url", String.class),
                        Boolean.TRUE.equals(r.get("host", Boolean.class)),
                        Boolean.TRUE.equals(r.get("here", Boolean.class)), instant(r.get("joined_at"))))
                .all();
    }

    private Mono<CurrentGame> currentGame(UUID roomId) {
        if (roomId == null) return Mono.empty();
        return db.sql("SELECT r.id, r.code, r.game_type, r.status, "
                        + "(SELECT count(*) FROM room_members rm WHERE rm.room_id=r.id) AS players FROM rooms r WHERE r.id=:id")
                .bind("id", roomId)
                .map((r, m) -> new CurrentGame(r.get("id", UUID.class), r.get("code", String.class),
                        r.get("game_type", String.class), gameStatus(r.get("status", String.class)),
                        ((Number) r.get("players")).intValue()))
                .one();
    }

    /** Words the app can show as they are: waiting → playing → finished. */
    static String gameStatus(String roomStatus) {
        return switch (roomStatus) {
            case "lobby" -> "waiting";
            case "in_game" -> "playing";
            default -> "finished";
        };
    }

    // ------------------------------------------------------------ helpers

    private Mono<Space> requireHost(UUID id, UUID user) {
        return space(id).filter(s -> s.active() && s.ownerId().equals(user))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("Only the host can do that")));
    }

    Mono<Space> space(UUID id) {
        return db.sql("SELECT * FROM huud_spaces WHERE id=:id").bind("id", id).fetch().one().map(HuudSpaceService::toSpace);
    }

    private Mono<Membership> membership(UUID id, UUID user) {
        return db.sql("SELECT left_at, removed FROM huud_space_members WHERE huud_space_id=:id AND user_id=:user")
                .bind("id", id).bind("user", user)
                .map((r, m) -> new Membership(instant(r.get("left_at")), Boolean.TRUE.equals(r.get("removed", Boolean.class))))
                .one();
    }

    private static Space toSpace(Map<String, Object> row) {
        return new Space((UUID) row.get("id"), (String) row.get("code"), (String) row.get("name"),
                (String) row.get("privacy"), (UUID) row.get("owner_id"), (UUID) row.get("created_by"),
                (String) row.get("status"), (UUID) row.get("current_room_id"),
                instant(row.get("created_at")), instant(row.get("ended_at")));
    }

    private static Instant instant(Object value) {
        if (value == null) return null;
        if (value instanceof Instant i) return i;
        if (value instanceof OffsetDateTime o) return o.toInstant();
        if (value instanceof java.time.LocalDateTime l) return l.toInstant(java.time.ZoneOffset.UTC);
        throw new IllegalStateException("unexpected timestamp " + value.getClass());
    }

    /** Off the Huud's voice room, best effort — LiveKit being down mustn't stop a removal. */
    private Mono<Void> dropFromVoice(UUID id, UUID user) {
        String room = HuudSpaceAccess.VOICE_PREFIX + id;
        return voice.remove(room, user.toString()).onErrorResume(e -> Mono.empty())
                .then(voiceSessions.removeMembership(user, room).onErrorResume(e -> Mono.empty()));
    }

    private Mono<Void> lock(String key) {
        return db.sql("SELECT 1 AS locked FROM pg_advisory_xact_lock(hashtextextended(:key,0))")
                .bind("key", key).fetch().all().then();
    }

    /** Everyone in the Huud refreshes it — what changed is in {@code event}. */
    private void notifyMembers(UUID id, String event, UUID by) {
        members(id, false).subscribe(p -> notify(p.userId(), id, event, by), e -> { });
    }

    private void notify(UUID user, UUID id, String event, UUID by) {
        inbox.notify(user, Map.of("type", "HUUD_SPACE",
                "data", Map.of("huudSpaceId", id.toString(), "event", event, "by", by.toString())));
    }
}
