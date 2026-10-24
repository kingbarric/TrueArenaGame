package app.truearena.api.huudspace;

import app.truearena.api.huudspace.HuudSpaceDtos.CurrentGame;
import app.truearena.api.huudspace.HuudSpaceDtos.MyHuud;
import app.truearena.api.huudspace.HuudSpaceDtos.HuudSpaceView;
import app.truearena.api.huudspace.HuudSpaceDtos.LiveHuud;
import app.truearena.api.huudspace.HuudSpaceDtos.PendingRequest;
import app.truearena.api.huudspace.HuudSpaceDtos.Person;
import app.truearena.api.huud.HuudService;
import app.truearena.api.calls.VoiceSessionService;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.push.PushNotificationService;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.room.RoomService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.UserRepository;
import app.truearena.room.RoomRuntimeRegistry;
import app.truearena.api.bot.BotRuntimeRegistry;
import com.fasterxml.jackson.databind.ObjectMapper;
import app.truearena.game.truearena.Presets;
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
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * Huuds — permanent social rooms. A Huud keeps its name, members, chat, code,
 * privacy and background for good; going <b>Live</b> is a hangout inside it
 * (voice, games, watching, requests), and ending Live resets just that.
 *
 * <p>Fields: {@code created_by} is the owner for good; {@code owner_id} is who
 * runs the Huud right now (the owner, or — while the owner is away during
 * Live — whoever joined the hangout next). Membership ends only by leaving or
 * being taken out; being away just takes you out of the Live hangout
 * ({@code live_at}). A Live hangout with no activity for 24 hours ends by itself.
 */
@Service
public class HuudSpaceService {

    /** No 0/O, 1/I/L: a code a child can read out loud without a mix-up. */
    static final String CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    static final int CODE_LENGTH = 6;
    static final int LIST_LIMIT = 40;
    static final List<String> NOTIFY = List.of("all", "online", "none");

    private static final SecureRandom RANDOM = new SecureRandom();

    private final DatabaseClient db;
    private final TransactionalOperator tx;
    private final InboxRegistry inbox;
    private final RoomService rooms;
    private final UserRepository users;
    private final VoiceSessionService voiceSessions;
    private final LiveKitRoomAdmin voice;
    private final PushNotificationService push;
    private final Duration hostGrace;
    private final Duration memberTimeout;
    private final Duration inactivityTimeout;
    private final RoomRuntimeRegistry runtimes;
    private final BotRuntimeRegistry bots;
    private final HuudSpaceAccess access;

    public HuudSpaceService(DatabaseClient db, ReactiveTransactionManager manager, InboxRegistry inbox,
                            RoomService rooms, UserRepository users, VoiceSessionService voiceSessions,
                            LiveKitRoomAdmin voice, PushNotificationService push, HuudSpaceAccess access,
                            @Value("${huud.host-grace:PT5M}") Duration hostGrace,
                            @Value("${huud.member-timeout:PT10M}") Duration memberTimeout,
                            @Value("${huud.inactivity-timeout:PT24H}") Duration inactivityTimeout,
                            RoomRuntimeRegistry runtimes, BotRuntimeRegistry bots) {
        this.db = db;
        this.tx = TransactionalOperator.create(manager);
        this.inbox = inbox;
        this.rooms = rooms;
        this.users = users;
        this.voiceSessions = voiceSessions;
        this.voice = voice;
        this.push = push;
        this.hostGrace = hostGrace;
        this.memberTimeout = memberTimeout;
        // An environment override may extend the window, never shorten the promised 24 hours.
        this.inactivityTimeout = inactivityTimeout.compareTo(Duration.ofHours(24)) < 0
                ? Duration.ofHours(24) : inactivityTimeout;
        this.runtimes = runtimes;
        this.bots = bots;
        this.access = access;
    }

    /** {@code ownerId}: running it now; {@code createdBy}: the owner. */
    record Space(UUID id, String code, String name, String privacy, UUID ownerId, UUID createdBy,
                 String status, UUID currentRoomId, String feedMessage, Instant sharedAt, String background,
                 Instant liveSince, Instant createdAt, Instant endedAt, UUID championshipId, boolean findingPlayers) {
        boolean active() {
            return "active".equals(status);
        }

        boolean live() {
            return active() && liveSince != null;
        }
    }

    record Membership(Instant leftAt, boolean removed, boolean canSpeak, Instant liveAt, boolean muted) {
        boolean in() {
            return leftAt == null && !removed;
        }

        boolean inLive() {
            return in() && liveAt != null;
        }
    }

    // ------------------------------------------------------------ your Huud

    /**
     * Your Huud: made the first time (and Live straight away — you made it to
     * hang out), the same one every time after. One Huud per person.
     */
    public Mono<HuudSpaceView> create(UUID user, String requestedName, String requestedPrivacy) {
        return create(user, requestedName, requestedPrivacy, null, null, null, false);
    }

    public Mono<HuudSpaceView> create(UUID user, String requestedName, String requestedPrivacy,
                                      String gameType, String message, boolean share) {
        return create(user, requestedName, requestedPrivacy, gameType, null, message, share);
    }

    public Mono<HuudSpaceView> create(UUID user, String requestedName, String requestedPrivacy,
                                      String gameType, String mode, String message, boolean share) {
        return create(user, requestedName, requestedPrivacy, gameType, mode, message, share, null);
    }

    public Mono<HuudSpaceView> create(UUID user, String requestedName, String requestedPrivacy,
                                      String gameType, String mode, String message, boolean share, Map<String, Object> gameConfig) {
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
                                            "INSERT INTO huud_spaces(code,name,privacy,owner_id,created_by,live_since,background) "
                                                    + "VALUES(:code,:name,:privacy,:user,:user,now(),'blank') RETURNING id")
                                    .bind("code", code).bind("name", name).bind("privacy", privacy).bind("user", user)
                                    .map((r, m) -> r.get("id", UUID.class)).one()
                                    .flatMap(id -> admitRow(id, user).then(enterLive(id, user)).thenReturn(id))))));
                })
                .flatMap(id -> space(id).flatMap(s -> !s.live() || gameType == null || gameType.isBlank()
                                || s.currentRoomId() != null ? Mono.<Void>empty()
                                : addGame(user, id, gameType, mode, false, gameConfig).then())
                        .then(share ? space(id).filter(Space::live).flatMap(s -> share(user, id, message)).then()
                                : Mono.<Void>empty())
                        .then(view(id, user)));
    }

    /** The Huud you own, if any. */
    /** For playhuud.com/huud/CODE: a Huud that exists, by its code. */
    public Mono<HuudSpaceDtos.InvitePreview> invitePreview(String rawCode) {
        String code = rawCode == null ? "" : rawCode.trim().toUpperCase();
        if (!code.matches("[A-Z0-9]{" + CODE_LENGTH + "}")) {
            return Mono.error(ApiExceptions.notFound("no Huud with that code"));
        }
        return db.sql("SELECT s.code, s.name, u.username, s.live_since IS NOT NULL AS live, "
                        + "(SELECT count(*) FROM huud_space_members m WHERE m.huud_space_id = s.id "
                        + "   AND m.left_at IS NULL AND NOT m.removed) AS members "
                        + "FROM huud_spaces s JOIN users u ON u.id = s.created_by "
                        + "WHERE s.code = :code AND s.status = 'active'")
                .bind("code", code)
                .map((r, m) -> new HuudSpaceDtos.InvitePreview(r.get("code", String.class), r.get("name", String.class),
                        r.get("username", String.class), Boolean.TRUE.equals(r.get("live", Boolean.class)),
                        ((Number) r.get("members")).intValue()))
                .one()
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no Huud with that code")));
    }

    public Mono<HuudSpaceView> current(UUID user) {
        return ownedId(user).flatMap(id -> view(id, user));
    }

    private Mono<UUID> ownedId(UUID user) {
        return db.sql("SELECT id FROM huud_spaces WHERE created_by=:user AND status='active'")
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

    // ------------------------------------------------------------ going Live

    /**
     * Owner only: turn the Huud Live and — if they like — tell the members.
     * "all": everyone who hasn't muted it, pushed to their phones too;
     * "online": only those with the app open; "none": nobody.
     */
    public Mono<HuudSpaceView> goLive(UUID user, UUID id, String notify) {
        String who = notify == null || notify.isBlank() ? "all" : notify;
        if (!NOTIFY.contains(who)) return Mono.error(ApiExceptions.badRequest("notify must be all, online or none"));
        return space(id).filter(s -> s.active() && s.createdBy().equals(user))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("Only the owner can take the Huud Live")))
                .flatMap(s -> s.live() ? Mono.just(false)
                        : tx.transactional(lock("huud-space:" + id)
                                .then(db.sql("UPDATE huud_spaces SET live_since=now(), owner_id=created_by "
                                                + "WHERE id=:id AND live_since IS NULL")
                                        .bind("id", id).fetch().rowsUpdated()))
                                .map(n -> n > 0))
                .flatMap(started -> enterLive(id, user)
                        .then(started && !"none".equals(who) ? announceLive(id, user, who) : Mono.<Void>empty()))
                .then(view(id, user));
    }

    /** "Eric's Huud is live" to members who haven't muted it. */
    private Mono<Void> announceLive(UUID id, UUID owner, String who) {
        return db.sql("SELECT m.user_id, s.name, r.game_type FROM huud_space_members m JOIN huud_spaces s ON s.id=m.huud_space_id "
                        + "LEFT JOIN rooms r ON r.id=s.current_room_id "
                        + "WHERE m.huud_space_id=:id AND m.left_at IS NULL AND NOT m.removed AND NOT m.muted AND m.user_id<>:owner")
                .bind("id", id).bind("owner", owner)
                .map((r, m) -> new Object[]{r.get("user_id", UUID.class), r.get("name", String.class), r.get("game_type", String.class)})
                .all().collectList()
                .doOnNext(rows -> {
                    if (rows.isEmpty()) return;
                    String name = (String) rows.get(0)[1];
                    String game = (String) rows.get(0)[2];
                    var targets = rows.stream().map(r -> (UUID) r[0])
                            .filter(u -> "all".equals(who) || inbox.isOnline(u)).toList();
                    targets.forEach(u -> notify(u, id, "live", owner));
                    if ("all".equals(who) && push != null && !targets.isEmpty()) {
                        push.sendToUsers(targets, name + " is live",
                                (game == null ? "Come hang out" : HuudService.gameName(game) + " starting soon") + " · Join Huud",
                                Map.of("type", "HUUD_SPACE", "huudSpaceId", id.toString(), "event", "live"));
                    }
                })
                .then();
    }

    /**
     * Owner only: end the Live hangout. The Huud stays — members, chat,
     * code, privacy, background — while the game, players, requests, watchers
     * and voice reset.
     */
    public Mono<HuudSpaceView> endLive(UUID user, UUID id) {
        return space(id).filter(s -> s.live() && s.createdBy().equals(user))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("Only the owner can end Live")))
                .flatMap(s -> stopLive(s, user))
                .then(view(id, user));
    }

    private Mono<Void> stopLive(Space s, UUID by) {
        UUID id = s.id();
        return livePeople(id).collectList().flatMap(people -> cancelWaitingGame(s, by)
                .then(tx.transactional(db.sql("UPDATE huud_spaces SET live_since=NULL, current_room_id=NULL, shared_at=NULL, "
                                        + "owner_id=created_by WHERE id=:id")
                                .bind("id", id).fetch().rowsUpdated()
                        .then(db.sql("DELETE FROM huud_space_requests WHERE huud_space_id=:id AND kind IN ('play','mic')")
                                .bind("id", id).fetch().rowsUpdated())
                        .then(db.sql("DELETE FROM huud_space_viewers WHERE huud_space_id=:id").bind("id", id).fetch().rowsUpdated())
                        .then(db.sql("UPDATE huud_space_members SET live_at=NULL, can_speak=false WHERE huud_space_id=:id")
                                .bind("id", id).fetch().rowsUpdated())
                        .then(endChampionshipWithLive(id))))
                .doOnSuccess(n -> people.forEach(p -> notify(p, id, "live-ended", by)))
                .then(Flux.fromIterable(people).concatMap(p -> dropFromVoice(id, p)).then())
                .then(dropPreviewListeners(id)));
    }

    /**
     * Ending Live calls off a championship still taking registrations and puts
     * a finished one's bracket away. One being played keeps going — its boards
     * are saved — and is still there when the Huud goes Live again.
     */
    private Mono<Long> endChampionshipWithLive(UUID id) {
        return db.sql("UPDATE championships SET status='cancelled', completed_at=now() "
                        + "WHERE huud_space_id=:id AND status='lobby'").bind("id", id).fetch().rowsUpdated()
                .then(db.sql("UPDATE huud_spaces SET championship_id=NULL WHERE id=:id AND championship_id IN "
                                + "(SELECT c.id FROM championships c WHERE c.status IN ('completed','cancelled'))")
                        .bind("id", id).fetch().rowsUpdated());
    }

    private Flux<UUID> livePeople(UUID id) {
        return db.sql("SELECT user_id FROM huud_space_members WHERE huud_space_id=:id AND live_at IS NOT NULL")
                .bind("id", id).map((r, m) -> r.get("user_id", UUID.class)).all();
    }

    /**
     * In the Live hangout (opening a Live Huud is walking in). The owner
     * coming back takes over again from whoever stepped in.
     */
    Mono<Void> enterLive(UUID id, UUID user) {
        return tx.transactional(lock("huud-space:" + id).then(db.sql(
                        "UPDATE huud_space_members m SET live_at=COALESCE(m.live_at, now()), last_seen_at=now() "
                        + "FROM huud_spaces s WHERE s.id=m.huud_space_id AND m.huud_space_id=:id AND m.user_id=:user "
                        + "AND s.live_since IS NOT NULL AND m.left_at IS NULL AND NOT m.removed RETURNING (m.live_at = m.last_seen_at) AS fresh")
                .bind("id", id).bind("user", user)
                .map((r, m) -> Boolean.TRUE.equals(r.get("fresh", Boolean.class))).all().next().defaultIfEmpty(false)
                .flatMap(fresh -> db.sql("UPDATE huud_spaces SET owner_id=created_by WHERE id=:id AND created_by=:user "
                                + "AND owner_id<>created_by AND live_since IS NOT NULL RETURNING id")
                        .bind("id", id).bind("user", user).map((r, m) -> true).all().next().defaultIfEmpty(false)
                        .doOnNext(back -> {
                            if (back) notifyMembers(id, "host", user);
                            else if (fresh) notifyMembers(id, "joined", user);
                        }))
                .then()));
    }

    // ------------------------------------------------------------ joining

    /** With a code. The same rules as anywhere else: the code finds the Huud, it doesn't open every door. */
    public Mono<HuudSpaceView> joinByCode(UUID user, String code) {
        String normalized = code == null ? "" : code.trim().toUpperCase();
        return db.sql("SELECT id FROM huud_spaces WHERE code=:code AND status='active'")
                .bind("code", normalized).map((r, m) -> r.get("id", UUID.class)).one()
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("No Huud has that code — check it and try again")))
                .flatMap(id -> join(user, id));
    }

    /**
     * Become a member — Live or not. Public → straight in. Friends → the
     * owner's friends straight in. Anyone else (and everyone, for a private
     * Huud) asks, unless invited or let in before. Members are told when the
     * Huud goes Live; while it's Live, joining walks you into the hangout —
     * listening, chatting and watching, not a seat in the game.
     */
    public Mono<HuudSpaceView> join(UUID user, UUID id) {
        return space(id).filter(Space::active)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("That Huud isn't here any more")))
                .flatMap(s -> membership(id, user).map(Optional::of).defaultIfEmpty(Optional.empty())
                        .flatMap(m -> {
                            if (m.isPresent() && m.get().removed()) {
                                return Mono.error(ApiExceptions.forbidden("You can't join this Huud"));
                            }
                            Mono<Boolean> straightIn = m.isPresent() && m.get().in() ? Mono.just(true) : mayWalkIn(s, user);
                            return blocked(user, s.createdBy()).flatMap(b -> b
                                    ? Mono.error(ApiExceptions.forbidden("You can't join this Huud"))
                                    : straightIn).flatMap(ok -> ok
                                    ? tx.transactional(lock("huud-space:" + id).then(admitRow(id, user)))
                                        .doOnSuccess(v -> { if (m.isEmpty() || !m.get().in()) notifyMembers(id, "member", user); })
                                        .then(enterLive(id, user))
                                        .then(view(id, user))
                                    : askToJoin(s, user).then(view(id, user)));
                        }));
    }

    /** Eligibility for the preview, without entering the hangout or refreshing activity. */
    private Mono<Boolean> mayWatch(Space s, UUID user) {
        return blocked(user, s.createdBy()).flatMap(blocked -> blocked ? Mono.just(false)
                : membership(s.id(), user).map(Optional::of).defaultIfEmpty(Optional.empty())
                .flatMap(member -> member.isPresent() && member.get().removed() ? Mono.just(false)
                        : member.isPresent() && member.get().in() ? Mono.just(true)
                        : canSee(s, user).flatMap(see -> see ? Mono.just(true)
                        : request(s.id(), user, "join").map("accepted"::equals).defaultIfEmpty(false))));
    }

    /** Look in and listen without joining, chatting, publishing or taking a seat. */
    public Mono<HuudSpaceView> watch(UUID user, UUID id) {
        return space(id).filter(Space::live)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("This Huud isn't live right now")))
                .flatMap(s -> mayWatch(s, user))
                .flatMap(ok -> !ok ? Mono.error(ApiExceptions.forbidden("This Huud isn't open to you"))
                        : tx.transactional(lock("huud-space:" + id).then(db.sql(
                                "INSERT INTO huud_space_viewers(huud_space_id,user_id) VALUES(:id,:user) "
                                        + "ON CONFLICT(huud_space_id,user_id) DO UPDATE SET last_seen_at=now()")
                                .bind("id", id).bind("user", user).fetch().rowsUpdated()))).then(view(id, user, false));
    }

    public static String previewIdentity(UUID user, UUID preview) { return "preview-" + user + "-" + preview; }

    /** A stale swipe must never disconnect a newer preview of the same Huud. */
    public Mono<Void> stopPreview(UUID user, UUID id, UUID preview) {
        return voice.remove(HuudSpaceAccess.VOICE_PREFIX + id, previewIdentity(user, preview));
    }

    private Mono<Void> dropUserPreviews(UUID id, UUID user) {
        String room = HuudSpaceAccess.VOICE_PREFIX + id;
        return voice.participantIds(room).flatMapMany(Flux::fromIterable)
                .filter(identity -> identity.startsWith("preview-" + user + "-"))
                .concatMap(identity -> voice.remove(room, identity)).then().onErrorResume(e -> Mono.empty());
    }

    private Mono<Void> dropPreviewListeners(UUID id) {
        String room = HuudSpaceAccess.VOICE_PREFIX + id;
        return voice.participantIds(room).flatMapMany(Flux::fromIterable)
                .filter(identity -> identity.startsWith("preview-"))
                .concatMap(identity -> voice.remove(room, identity)).then().onErrorResume(e -> Mono.empty());
    }

    /** A live preview needs a fresh viewer lease and must still pass the privacy rules. */
    private Mono<Void> prunePreviewListeners(UUID id) {
        String room = HuudSpaceAccess.VOICE_PREFIX + id;
        return voice.participantIds(room).flatMapMany(Flux::fromIterable)
                .filter(identity -> identity.startsWith("preview-"))
                .concatMap(identity -> {
                    UUID user;
                    try { user = UUID.fromString(identity.substring("preview-".length(), "preview-".length() + 36)); }
                    catch (IllegalArgumentException | IndexOutOfBoundsException e) { return voice.remove(room, identity); }
                    return db.sql("SELECT EXISTS(SELECT 1 FROM huud_space_viewers WHERE huud_space_id=:id "
                                    + "AND user_id=:user AND last_seen_at > now()-interval '60 seconds') AS ok")
                            .bind("id", id).bind("user", user)
                            .map((r, m) -> Boolean.TRUE.equals(r.get("ok", Boolean.class))).one()
                            .flatMap(fresh -> fresh ? space(id).flatMap(s -> mayWatch(s, user)) : Mono.just(false))
                            .flatMap(ok -> ok ? Mono.empty() : voice.remove(room, identity));
                }).then();
    }

    /** Blocking also stops either person's preview of the other's hosted Huud. */
    public Mono<Void> stopBlockedPreviews(UUID a, UUID b) {
        return db.sql("SELECT id,created_by FROM huud_spaces WHERE status='active' AND live_since IS NOT NULL "
                        + "AND created_by IN (:a,:b)")
                .bind("a", a).bind("b", b)
                .map((r, m) -> Map.entry(r.get("id", UUID.class), r.get("created_by", UUID.class))).all()
                .concatMap(s -> dropUserPreviews(s.getKey(), s.getValue().equals(a) ? b : a).onErrorResume(e -> Mono.empty()))
                .then();
    }

    /** People looking in right now who aren't in the Live hangout. */
    static String watchingSql(String huudId) {
        return "(SELECT count(*) FROM huud_space_viewers v WHERE v.huud_space_id=" + huudId
                + " AND v.last_seen_at > now() - interval '60 seconds' AND NOT EXISTS(SELECT 1 FROM huud_space_members wm "
                + "WHERE wm.huud_space_id=v.huud_space_id AND wm.user_id=v.user_id AND wm.live_at IS NOT NULL))";
    }

    private Mono<Integer> watching(UUID id) {
        return db.sql("SELECT " + watchingSql(":id") + " AS n").bind("id", id)
                .map((r, m) -> ((Number) r.get("n")).intValue()).one();
    }

    /** No asking needed: the owner, anyone for a public Huud, the owner's friends, or someone invited/let in. */
    Mono<Boolean> mayWalkIn(Space s, UUID user) {
        if (s.createdBy().equals(user) || "public".equals(s.privacy())) return Mono.just(true);
        Mono<Boolean> letIn = request(s.id(), user, "join").map("accepted"::equals).defaultIfEmpty(false);
        if (!"friends".equals(s.privacy())) return letIn;
        return friends(user, s.createdBy()).flatMap(friend -> friend ? Mono.just(true) : letIn);
    }

    /** Knock on the door. A host who just said no isn't asked again straight away. */
    private Mono<Void> askToJoin(Space s, UUID user) {
        return db.sql("SELECT status, answered_at > now() - interval '5 minutes' AS recent FROM huud_space_requests "
                        + "WHERE huud_space_id=:id AND user_id=:user AND kind='join'")
                .bind("id", s.id()).bind("user", user)
                .map((r, m) -> "declined".equals(r.get("status", String.class))
                        && Boolean.TRUE.equals(r.get("recent", Boolean.class)))
                .one().defaultIfEmpty(false)
                .flatMap(tooSoon -> tooSoon
                        ? Mono.error(ApiExceptions.conflict("The host said not right now — try again in a few minutes"))
                        : upsertRequest(s.id(), user, "join", null)
                                .doOnSuccess(v -> notify(s.ownerId(), s.id(), "request", user)));
    }

    Mono<Void> upsertRequest(UUID id, UUID user, String kind, UUID roomId) {
        var sql = db.sql("INSERT INTO huud_space_requests(huud_space_id,user_id,kind,room_id) VALUES(:id,:user,:kind,:room) "
                        + "ON CONFLICT(huud_space_id,user_id,kind) DO UPDATE SET status='pending',room_id=EXCLUDED.room_id,"
                        + "created_at=now(),answered_at=NULL")
                .bind("id", id).bind("user", user).bind("kind", kind);
        return (roomId == null ? sql.bindNull("room", UUID.class) : sql.bind("room", roomId)).fetch().rowsUpdated().then();
    }

    /** The present admin, otherwise the next joiner and players at the current table. */
    Flux<UUID> micApprovers(UUID id) {
        return db.sql("""
            WITH present AS (
                SELECT m.user_id, m.live_at, m.joined_at FROM huud_space_members m
                JOIN huud_spaces s ON s.id=m.huud_space_id JOIN users u ON u.id=m.user_id
                WHERE s.id=:id AND s.status='active' AND s.live_since IS NOT NULL
                AND m.left_at IS NULL AND NOT m.removed AND m.live_at IS NOT NULL AND NOT u.is_bot
                AND m.last_seen_at > now() - make_interval(secs => :grace)
            ), present_host AS (
                SELECT p.user_id FROM present p JOIN huud_spaces s ON s.id=:id AND s.owner_id=p.user_id
            )
            SELECT p.user_id FROM present p JOIN huud_spaces s ON s.id=:id
            WHERE p.user_id IN (SELECT user_id FROM present_host)
               OR (NOT EXISTS(SELECT 1 FROM present_host) AND (
                    p.user_id=(SELECT user_id FROM present ORDER BY live_at, joined_at, user_id LIMIT 1)
                    OR EXISTS(SELECT 1 FROM room_members rm JOIN rooms r ON r.id=rm.room_id
                              WHERE rm.user_id=p.user_id AND r.id=s.current_room_id AND r.status IN ('lobby','in_game'))
                    OR EXISTS(SELECT 1 FROM room_members rm JOIN championship_matches cm ON cm.room_id=rm.room_id
                              JOIN championships c ON c.id=cm.championship_id
                              WHERE rm.user_id=p.user_id AND c.huud_space_id=s.id AND cm.status='active')
               ))
            """).bind("id", id).bind("grace", (double) hostGrace.toSeconds())
                .map((row, metadata) -> row.get("user_id", UUID.class)).all();
    }

    Mono<Space> requireMicApprover(UUID id, UUID user) {
        return micApprovers(id).any(user::equals).flatMap(allowed -> allowed ? space(id)
                : Mono.error(ApiExceptions.forbidden("Only the present admin or their mic cover can answer")));
    }

    Mono<Void> answerRow(UUID id, UUID user, String kind, boolean accepted) {
        return db.sql("INSERT INTO huud_space_requests(huud_space_id,user_id,kind,status,answered_at) "
                        + "VALUES(:id,:user,:kind,:status,now()) ON CONFLICT(huud_space_id,user_id,kind) "
                        + "DO UPDATE SET status=EXCLUDED.status,answered_at=now()")
                .bind("id", id).bind("user", user).bind("kind", kind).bind("status", accepted ? "accepted" : "declined")
                .fetch().rowsUpdated().then();
    }

    Mono<String> request(UUID id, UUID user, String kind) {
        return db.sql("SELECT status FROM huud_space_requests WHERE huud_space_id=:id AND user_id=:user AND kind=:kind")
                .bind("id", id).bind("user", user).bind("kind", kind)
                .map((r, m) -> r.get("status", String.class)).one();
    }

    /** A member (again). Someone coming back after leaving joins the end of the line. */
    Mono<Void> admitRow(UUID id, UUID user) {
        return db.sql("INSERT INTO huud_space_members(huud_space_id,user_id) VALUES(:id,:user) "
                        + "ON CONFLICT(huud_space_id,user_id) DO UPDATE SET "
                        + "joined_at=CASE WHEN huud_space_members.left_at IS NULL THEN huud_space_members.joined_at ELSE now() END, "
                        + "left_at=NULL, last_seen_at=now() WHERE NOT huud_space_members.removed")
                .bind("id", id).bind("user", user).fetch().rowsUpdated().then();
    }

    Mono<Boolean> canSee(Space s, UUID user) {
        if (s.createdBy().equals(user) || "public".equals(s.privacy()) || s.findingPlayers()) return Mono.just(true);
        if (!"friends".equals(s.privacy())) return Mono.just(false);
        return friends(user, s.createdBy());
    }

    /** Either of the two has blocked the other. */
    public static String blockedSql(String a, String b) {
        return "EXISTS(SELECT 1 FROM player_blocks pb WHERE (pb.blocker_id=" + a + " AND pb.blocked_id=" + b + ") "
                + "OR (pb.blocker_id=" + b + " AND pb.blocked_id=" + a + "))";
    }

    Mono<Boolean> blocked(UUID a, UUID b) {
        if (a.equals(b)) return Mono.just(false);
        return db.sql("SELECT " + blockedSql(":a", ":b") + " AS blocked").bind("a", a).bind("b", b)
                .map((r, m) -> Boolean.TRUE.equals(r.get("blocked", Boolean.class))).one();
    }

    Mono<Boolean> friends(UUID a, UUID b) {
        return db.sql("SELECT EXISTS(SELECT 1 FROM friends WHERE status='accepted' "
                        + "AND low_user_id=LEAST(:a,:b) AND high_user_id=GREATEST(:a,:b)) AS ok")
                .bind("a", a).bind("b", b).map((r, m) -> Boolean.TRUE.equals(r.get("ok", Boolean.class))).one();
    }

    // ------------------------------------------------------------ leaving / deleting

    /**
     * Leave the Huud for good: no longer a member, no more Live notifications
     * (until you rejoin or accept an invite). Navigating away is not leaving.
     * The owner can't leave their own Huud — they can delete it.
     */
    public Mono<Void> leave(UUID user, UUID id) {
        return space(id).filter(Space::active)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("That Huud isn't here any more")))
                .flatMap(s -> {
                    if (s.createdBy().equals(user)) {
                        return Mono.error(ApiExceptions.conflict("It's your Huud — you can delete it in settings instead"));
                    }
                    return tx.transactional(lock("huud-space:" + id)
                                    .then(db.sql("UPDATE huud_space_members SET left_at=now(), live_at=NULL, can_speak=false "
                                                    + "WHERE huud_space_id=:id AND user_id=:user AND left_at IS NULL")
                                            .bind("id", id).bind("user", user).fetch().rowsUpdated())
                                    .flatMap(n -> n > 0 && s.live() && s.ownerId().equals(user)
                                            ? handOffOrOwner(id).thenReturn(n) : Mono.just(n)))
                            .doOnSuccess(n -> { if (n != null && n > 0) notifyMembers(id, "left", user); })
                            .then(dropFromVoice(id, user));
                });
    }

    /** Owner only: delete the Huud for everyone. It can't be undone. */
    public Mono<Void> delete(UUID user, UUID id) {
        return space(id).filter(s -> s.active() && s.createdBy().equals(user))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("Only the owner can delete the Huud")))
                .flatMap(s -> (s.live() ? stopLive(s, user) : Mono.<Void>empty())
                        .then(members(id).collectList())
                        .flatMap(people -> db.sql("UPDATE huud_spaces SET status='ended', ended_at=now(), live_since=NULL "
                                        + "WHERE id=:id").bind("id", id).fetch().rowsUpdated()
                                .then(db.sql("UPDATE huud_space_members SET left_at=COALESCE(left_at, now()), live_at=NULL "
                                        + "WHERE huud_space_id=:id").bind("id", id).fetch().rowsUpdated())
                                .doOnSuccess(n -> people.forEach(p -> notify(p.userId(), id, "deleted", user)))))
                .then();
    }

    /** Host only: takes someone out of the Huud; they can't come back into this one. */
    public Mono<Void> remove(UUID host, UUID id, UUID target) {
        if (host.equals(target)) return Mono.error(ApiExceptions.badRequest("to go, tap Leave"));
        return requireHost(id, host).flatMap(s -> s.createdBy().equals(target)
                        ? Mono.error(ApiExceptions.forbidden("You can't take the owner out of their own Huud"))
                        : db.sql("UPDATE huud_space_members SET left_at=now(), live_at=NULL, removed=true "
                                        + "WHERE huud_space_id=:id AND user_id=:target")
                                .bind("id", id).bind("target", target).fetch().rowsUpdated())
                .doOnSuccess(n -> {
                    notify(target, id, "removed", host);
                    notifyMembers(id, "left", target);
                })
                .then(dropFromVoice(id, target));
    }

    /** Your own notifications from this Huud: muted, or not. */
    public Mono<HuudSpaceView> mute(UUID user, UUID id, boolean muted) {
        return requireMember(id, user)
                .flatMap(s -> db.sql("UPDATE huud_space_members SET muted=:muted WHERE huud_space_id=:id AND user_id=:user")
                        .bind("muted", muted).bind("id", id).bind("user", user).fetch().rowsUpdated())
                .then(view(id, user));
    }

    public Mono<HuudSpaceView> update(UUID host, UUID id, String name, String privacy) {
        return update(host, id, name, privacy, null);
    }

    /** Owner (or whoever is hosting): name, privacy and backdrop; anything left null stays as it is. */
    public Mono<HuudSpaceView> update(UUID host, UUID id, String name, String privacy, String background) {
        if (background != null && !"default".equals(background) && !HuudSpaceDtos.BACKGROUNDS.contains(background)) {
            return Mono.error(ApiExceptions.badRequest("Pick one of the backgrounds"));
        }
        return requireHost(id, host).flatMap(s -> {
            String nextPrivacy = privacy == null ? s.privacy() : privacyOrDefault(privacy);
            String nextName = name == null ? s.name() : nameOrDefault(name, s.name());
            String nextBackground = background == null ? s.background() : ("default".equals(background) ? null : background);
            var sql = db.sql("UPDATE huud_spaces SET name=:name,privacy=:privacy,background=:background WHERE id=:id")
                    .bind("name", nextName).bind("privacy", nextPrivacy).bind("id", id);
            return (nextBackground == null ? sql.bindNull("background", String.class) : sql.bind("background", nextBackground))
                    .fetch().rowsUpdated()
                    .flatMap(n -> nextPrivacy.equals(s.privacy()) ? Mono.just(n)
                            : dropPreviewListeners(id).thenReturn(n));
        }).doOnSuccess(n -> notifyMembers(id, "updated", host)).then(view(id, host));
    }

    /**
     * While Live and the host is away: the person who joined the hangout next
     * (and is still in it) runs it for now — guests can't. The owner taking
     * back over happens when they walk back in.
     */
    Mono<UUID> handOff(UUID id) {
        return db.sql("UPDATE huud_spaces s SET owner_id=next.user_id FROM ("
                        + "SELECT m.user_id FROM huud_space_members m JOIN users u ON u.id=m.user_id "
                        + "WHERE m.huud_space_id=:id AND m.live_at IS NOT NULL AND m.left_at IS NULL AND NOT m.removed "
                        + "AND NOT u.is_guest AND m.user_id <> (SELECT owner_id FROM huud_spaces WHERE id=:id) "
                        + "AND m.last_seen_at > now() - make_interval(secs => :grace) "
                        + "ORDER BY m.live_at, m.user_id LIMIT 1) next "
                        + "WHERE s.id=:id AND s.status='active' AND s.live_since IS NOT NULL RETURNING s.owner_id")
                .bind("id", id).bind("grace", (double) hostGrace.toSeconds())
                .map((r, m) -> r.get("owner_id", UUID.class)).one();
    }

    /** Someone else runs it — or, with nobody to, it goes back to the owner. */
    private Mono<UUID> handOffOrOwner(UUID id) {
        return handOff(id).switchIfEmpty(db.sql("UPDATE huud_spaces SET owner_id=created_by WHERE id=:id RETURNING owner_id")
                .bind("id", id).map((r, m) -> r.get("owner_id", UUID.class)).one());
    }

    // ------------------------------------------------------------ presence

    /** The app calls this while it's open: keeps you in any Live hangout you're in. */
    public Mono<Void> heartbeat(UUID user) {
        return db.sql("SELECT s.id FROM huud_spaces s JOIN huud_space_members m ON m.huud_space_id=s.id "
                        + "WHERE s.status='active' AND s.live_since IS NOT NULL AND m.user_id=:user "
                        + "AND m.left_at IS NULL AND NOT m.removed")
                .bind("user", user).map((r, m) -> r.get("id", UUID.class)).all()
                .concatMap(id -> tx.transactional(lock("huud-space:" + id).then(db.sql(
                        "UPDATE huud_space_members m SET last_seen_at=now() FROM huud_spaces s "
                        + "WHERE s.id=m.huud_space_id AND s.live_since IS NOT NULL AND m.user_id=:user "
                        + "AND s.id=:id AND m.left_at IS NULL AND NOT m.removed")
                        .bind("user", user).bind("id", id).fetch().rowsUpdated())))
                .then();
    }

    /**
     * Scheduled. Being away only takes you out of the Live hangout — never
     * out of the Huud. A host who's away is covered by the next person in the
     * hangout. Live ends only after at least 24 hours with no member, viewer,
     * game or voice activity. An abandoned game is not proof of inactivity.
     */
    public Mono<Void> expire() {
        return db.sql("SELECT id FROM huud_spaces WHERE status='active' AND live_since IS NOT NULL")
                .map((r, m) -> r.get("id", UUID.class)).all()
                .concatMap(id -> refreshConnectedActivity(id).then(prunePreviewListeners(id))).then()
                .thenMany(db.sql("UPDATE huud_space_members SET live_at=NULL, can_speak=false WHERE live_at IS NOT NULL "
                        + "AND last_seen_at < now() - make_interval(secs => :secs) RETURNING huud_space_id, user_id")
                .bind("secs", (double) memberTimeout.toSeconds())
                .map((r, m) -> Map.entry(r.get("huud_space_id", UUID.class), r.get("user_id", UUID.class))).all())
                .concatMap(gone -> dropFromVoice(gone.getKey(), gone.getValue())
                        .doOnSuccess(v -> notifyMembers(gone.getKey(), "away", gone.getValue())))
                .then(db.sql("SELECT s.id, s.owner_id FROM huud_spaces s WHERE s.status='active' AND s.live_since IS NOT NULL "
                                + "AND NOT EXISTS(SELECT 1 FROM huud_space_members m WHERE m.huud_space_id=s.id AND m.user_id=s.owner_id "
                                + "AND m.live_at IS NOT NULL AND m.last_seen_at > now() - make_interval(secs => :secs))")
                        .bind("secs", (double) hostGrace.toSeconds())
                        .map((r, m) -> Map.entry(r.get("id", UUID.class), r.get("owner_id", UUID.class))).all()
                        .concatMap(absent -> tx.transactional(lock("huud-space:" + absent.getKey()).then(handOff(absent.getKey())))
                                .doOnNext(next -> notifyMembers(absent.getKey(), "host", absent.getValue())))
                        .then())
                .thenMany(db.sql("SELECT s.id FROM huud_spaces s WHERE s.status='active' AND s.live_since IS NOT NULL "
                                + "AND " + inactiveSql("s"))
                        .bind("idle", (double) inactivityTimeout.toSeconds())
                        .map((r, m) -> r.get("id", UUID.class)).all())
                .concatMap(this::endIfInactive)
                .then();
    }

    /** Persistent activity evidence survives a server restart; stale seats/room statuses don't count as presence. */
    private static String inactiveSql(String s) {
        String cutoff = "now() - make_interval(secs => :idle)";
        return s + ".live_since <= " + cutoff
                + " AND NOT EXISTS(SELECT 1 FROM huud_space_members m WHERE m.huud_space_id=" + s + ".id "
                + "AND GREATEST(m.last_seen_at,m.left_at) > " + cutoff + ")"
                + " AND NOT EXISTS(SELECT 1 FROM huud_space_viewers v WHERE v.huud_space_id=" + s + ".id "
                + "AND v.last_seen_at > " + cutoff + ")"
                + " AND NOT EXISTS(SELECT 1 FROM huud_space_messages c WHERE c.huud_space_id=" + s + ".id "
                + "AND c.created_at > " + cutoff + ")"
                + " AND NOT EXISTS(SELECT 1 FROM huud_space_requests q WHERE q.huud_space_id=" + s + ".id "
                + "AND GREATEST(q.created_at,q.answered_at) > " + cutoff + ")"
                + " AND NOT EXISTS(SELECT 1 FROM rooms r WHERE (r.huud_space_id=" + s + ".id OR r.id=" + s + ".current_room_id) "
                + "AND (r.created_at > " + cutoff + " OR EXISTS(SELECT 1 FROM game_sessions g WHERE g.room_id=r.id "
                + "AND (GREATEST(g.started_at,g.ended_at) > " + cutoff
                + " OR EXISTS(SELECT 1 FROM game_events e WHERE e.game_session_id=g.id AND e.created_at > " + cutoff + ")))))"
                + " AND NOT EXISTS(SELECT 1 FROM voice_session_participants p JOIN voice_sessions v ON v.id=p.voice_session_id "
                + "WHERE (v.room_name='huud-' || " + s + ".id::text OR v.room_name LIKE 'huud-' || " + s + ".id::text || '-m-%') "
                + "AND p.last_seen_at > " + cutoff + ")";
    }

    /** Actual sockets/media supplement app heartbeats, including members browsing elsewhere. */
    private Mono<Void> refreshConnectedActivity(UUID id) {
        Mono<Set<UUID>> onlineMembers = db.sql("SELECT user_id FROM huud_space_members "
                        + "WHERE huud_space_id=:id AND left_at IS NULL AND NOT removed")
                .bind("id", id).map((r, m) -> r.get("user_id", UUID.class)).all()
                .filter(inbox::isOnline).collect(HashSet<UUID>::new, Set::add).map(p -> p);
        Flux<String> gamePeople = db.sql("SELECT id FROM rooms WHERE huud_space_id=:id "
                        + "OR id=(SELECT current_room_id FROM huud_spaces WHERE id=:id)")
                .bind("id", id).map((r, m) -> r.get("id", UUID.class)).all()
                .flatMap(room -> runtimes.find(room).map(rt -> Flux.concat(
                        Flux.fromIterable(rt.connectedUserIds), Flux.fromIterable(rt.spectatorUserIds))).orElse(Flux.empty()));
        // Failure/timeout propagates: we cannot confirm an empty voice room, so this sweep must not end Live.
        Flux<String> voicePeople = access.voiceRooms(id)
                .concatMap(room -> voice.participantIds(room).timeout(Duration.ofSeconds(5)))
                .flatMapIterable(p -> p);
        return Mono.zip(onlineMembers, Flux.concat(gamePeople, voicePeople)
                        .flatMap(person -> {
                            try { return Mono.just(UUID.fromString(person)); }
                            catch (IllegalArgumentException ignored) { return Mono.empty(); }
                        }).collect(HashSet<UUID>::new, Set::add))
                .flatMap(t -> {
                    t.getT1().addAll(t.getT2());
                    return Flux.fromIterable(t.getT1()).concatMap(user -> db.sql(
                                    "UPDATE huud_space_members m SET last_seen_at=now() FROM users u "
                                            + "WHERE m.huud_space_id=:id AND m.user_id=:user AND m.left_at IS NULL "
                                            + "AND NOT m.removed AND u.id=m.user_id AND NOT u.is_bot")
                            .bind("id", id).bind("user", user).fetch().rowsUpdated()
                            .flatMap(n -> n > 0 ? Mono.just(n) : db.sql(
                                    "INSERT INTO huud_space_viewers(huud_space_id,user_id) "
                                            + "SELECT :id,id FROM users WHERE id=:user AND NOT is_bot "
                                            + "ON CONFLICT(huud_space_id,user_id) DO UPDATE SET last_seen_at=now()")
                                    .bind("id", id).bind("user", user).fetch().rowsUpdated())).then();
                });
    }

    /** Recheck under the same lock as joins; a return after the candidate scan cancels expiry. */
    private Mono<Void> endIfInactive(UUID id) {
        return tx.transactional(lock("huud-space:" + id)
                .then(refreshConnectedActivity(id))
                .then(db.sql("SELECT s.id FROM huud_spaces s WHERE s.id=:id AND s.status='active' "
                                + "AND s.live_since IS NOT NULL AND " + inactiveSql("s"))
                        .bind("id", id).bind("idle", (double) inactivityTimeout.toSeconds())
                        .map((r, m) -> r.get("id", UUID.class)).one())
                .flatMap(found -> space(found).flatMap(s -> endAbandonedGame(s).then(stopLive(s, s.createdBy())))));
    }

    /** Only reached after the 24-hour activity and actual-presence checks; never manufactures a winner. */
    private Mono<Void> endAbandonedGame(Space s) {
        if (s.currentRoomId() == null) return Mono.empty();
        UUID room = s.currentRoomId();
        return db.sql("UPDATE rooms SET status='ended' WHERE id=:room AND status='in_game' RETURNING id")
                .bind("room", room).map((r, m) -> r.get("id", UUID.class)).one()
                .flatMap(ended -> db.sql("UPDATE game_sessions SET ended_at=now(),phase='Abandoned' "
                                + "WHERE room_id=:room AND ended_at IS NULL")
                        .bind("room", room).fetch().rowsUpdated()
                        .doOnSuccess(n -> {
                            bots.stopRoom(room);
                            runtimes.find(room).ifPresent(rt -> {
                                rt.cancelTimer();
                                rt.bus.tryEmitNext(new app.truearena.room.LobbyBroadcast("ROOM_CANCELLED",
                                        Map.of("roomId", room.toString())));
                            });
                            runtimes.remove(room);
                        })).then();
    }

    // ------------------------------------------------------------ games

    /**
     * Host only: start setting up a game in the Huud. One game at a time — a
     * game that's waiting or being played has to finish (or be put away) first.
     */
    public Mono<RoomView> addGame(UUID host, UUID id, String gameType) {
        return addGame(host, id, gameType, null, false);
    }

    public Mono<RoomView> addGame(UUID host, UUID id, String gameType, boolean rematch) {
        return addGame(host, id, gameType, null, rematch);
    }

    /**
     * {@code mode} is Whot's "classic" (the default) or "tell"; other games
     * have none. With {@code rematch}, the last game's players who are still
     * in the Huud get their seats back straight away, in the last game's mode;
     * anyone missing just leaves a free seat for the queue.
     */
    public Mono<RoomView> addGame(UUID host, UUID id, String gameType, String mode, boolean rematch) {
        return addGame(host, id, gameType, mode, rematch, null);
    }

    public Mono<RoomView> addGame(UUID host, UUID id, String gameType, String mode, boolean rematch,
                                  Map<String, Object> requestedConfig) {
        Mono<Optional<CurrentGame>> last = !rematch ? Mono.just(Optional.empty())
                : space(id).flatMap(s -> currentGame(s.currentRoomId(), null)).map(Optional::of)
                        .defaultIfEmpty(Optional.empty());
        return last.flatMap(game -> {
            Mono<Map<String, Object>> previous = rematch && game.isPresent() && game.get().gameType().equals(gameType)
                    ? db.sql("SELECT game_config FROM rooms WHERE id=:id").bind("id", game.get().roomId())
                        .map((r, m) -> readRules(r.get("game_config", String.class))).one().defaultIfEmpty(Map.of())
                    : Mono.just(Map.of());
            return previous.flatMap(savedConfig -> {
            String chosen = mode != null || game.isEmpty() || !game.get().gameType().equals(gameType)
                    ? mode : game.get().mode();
            Map<String, Object> config;
            try {
                config = gameConfigFor(gameType, chosen, requestedConfig == null ? savedConfig : requestedConfig);
            } catch (IllegalArgumentException e) {
                return Mono.error(ApiExceptions.badRequest(e.getMessage()));
            }
            Mono<List<UUID>> again = game.map(g -> Flux.fromIterable(g.playerIds())
                            .filter(p -> !p.equals(host))
                            .filterWhen(p -> membership(id, p).map(Membership::in).defaultIfEmpty(false))
                            .collectList())
                    .orElse(Mono.just(List.of()));
            return again.flatMap(players -> addGameFresh(host, id, gameType, config)
                    .flatMap(room -> Flux.fromIterable(players)
                            .concatMap(p -> rooms.join(room.code(), p, null).onErrorResume(e -> Mono.empty()))
                            .then(rooms.get(room.id(), host))));
            });
        });
    }

    private static Map<String, Object> readRules(String json) {
        try {
            return json == null || json.isBlank() ? Map.of() : JSON.readValue(json, new com.fasterxml.jackson.core.type.TypeReference<Map<String, Object>>() {});
        } catch (Exception e) {
            throw new IllegalArgumentException("The previous game rules could not be read");
        }
    }

    static Map<String, Object> gameConfigFor(String gameType, String mode, Map<String, Object> requested) {
        Map<String, Object> base = gameConfigFor(gameType, mode);
        if (!"whot".equals(gameType) || requested == null || requested.isEmpty()) return base;
        var defaults = app.truearena.game.whot.WhotConfig.defaults();
        Map<String, Object> config = new java.util.LinkedHashMap<>(Map.of(
                "turnSeconds", defaults.turnSeconds(), "startingHand", defaults.startingHand(),
                "includeWhot", defaults.includeWhot(), "pickTwo", defaults.pickTwo(),
                "pickTwoStacking", defaults.pickTwoStacking(), "generalMarket", defaults.generalMarket(),
                "holdOn", defaults.holdOn(), "suspension", defaults.suspension(),
                "tellRule", defaults.tellRule(), "tellMinCards", defaults.tellMinCards()));
        for (var entry : requested.entrySet()) {
            if ("mode".equals(entry.getKey())) continue; // The explicit chosen mode remains authoritative.
            if (!config.containsKey(entry.getKey())) throw new IllegalArgumentException("Unknown Whot rule: " + entry.getKey());
            Object prior = config.get(entry.getKey());
            Object value = entry.getValue();
            if (prior instanceof Boolean && !(value instanceof Boolean)
                    || prior instanceof Integer && (!(value instanceof Number n) || n.doubleValue() != n.intValue())
                    || prior instanceof String && !(value instanceof String)) {
                throw new IllegalArgumentException("Invalid Whot rule: " + entry.getKey());
            }
            config.put(entry.getKey(), value);
        }
        config.put("mode", base.get("mode"));
        try {
            JSON.convertValue(config, app.truearena.game.whot.WhotConfig.class);
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Invalid Whot rules: check cards, turn time and Tell settings");
        }
        return config;
    }

    /** The room's rules for a Huud game: only Whot has a choice to make — Classic or The Tell. */
    static Map<String, Object> gameConfigFor(String gameType, String mode) {
        if ("slayhuud".equals(gameType)) return slayConfigFor(mode);
        if ("truearena".equals(gameType)) return traitorsConfigFor(mode);
        if ("draughts".equals(gameType)) return draughtsConfigFor(mode);
        if (!"whot".equals(gameType)) return null;
        String m = mode == null || mode.isBlank() ? "classic" : mode.trim().toLowerCase();
        if (!WHOT_MODES.contains(m)) throw new IllegalArgumentException("Whot mode must be classic or tell");
        return Map.of("mode", m);
    }

    /** Whot's modes, and how many seats each puts at a Huud table. The Tell plays 4, 6 or 8 in pairs. */
    private static final Set<String> WHOT_MODES = Set.of("classic", "tell");
    private static final int TELL_SEATS = 8;

    /**
     * SlayHuud in a Huud: a Style Battle for two, or a Group Show that starts
     * with 4 and seats up to 8. SlayHuud picks the theme when the room opens.
     */
    private static final Set<String> SLAY_MODES = Set.of("battle", "group");
    private static final int SLAY_SHOW_SEATS = 8;

    static Map<String, Object> slayConfigFor(String mode) {
        String m = mode == null || mode.isBlank() ? "battle" : mode.trim().toLowerCase();
        if (!SLAY_MODES.contains(m)) throw new IllegalArgumentException("SlayHuud mode must be battle or group");
        return Map.of("mode", m, "seats", "group".equals(m) ? SLAY_SHOW_SEATS : 2);
    }

    /**
     * Traitors in a Huud plays one of the five built-in modes, rules and all;
     * the table seats that mode's most players. No mode keeps the old default.
     */
    @SuppressWarnings("unchecked")
    static Map<String, Object> traitorsConfigFor(String mode) {
        if (mode == null || mode.isBlank()) return null;
        Presets.Mode preset = Presets.bySlug(mode.trim());
        if (preset == null) throw new IllegalArgumentException("Pick one of the Traitors modes");
        return JSON.convertValue(preset.config(), Map.class);
    }

    /**
     * Draughts' rules in a Huud: "casual" (captures optional), "seizure"
     * (optional, but a missed capture can cost the piece) or "official"
     * (captures forced, the most pieces). No mode keeps the casual default.
     */
    private static final Set<String> DRAUGHTS_MODES = Set.of("casual", "seizure", "official");

    static Map<String, Object> draughtsConfigFor(String mode) {
        if (mode == null || mode.isBlank()) return null;
        String m = mode.trim().toLowerCase();
        if (!DRAUGHTS_MODES.contains(m)) throw new IllegalArgumentException("Draughts rules must be casual, seizure or official");
        return Map.of("mandatoryCapture", "official".equals(m), "seizure", "seizure".equals(m));
    }

    static int seatsFor(String gameType, String mode) {
        if ("truearena".equals(gameType) && mode != null && Presets.bySlug(mode) != null) {
            return Presets.bySlug(mode).config().table().maxPlayers();
        }
        if ("whot".equals(gameType) && "tell".equals(mode)) return TELL_SEATS;
        if ("slayhuud".equals(gameType) && "group".equals(mode)) return SLAY_SHOW_SEATS;
        return HuudService.seatsFor(gameType);
    }

    private static final ObjectMapper JSON = new ObjectMapper();

    /** Draughts' rules from the room's stored config: casual unless set otherwise. */
    private static String draughtsModeOf(String gameConfig) {
        try {
            Map<?, ?> raw = gameConfig == null || gameConfig.isBlank() ? Map.of() : JSON.readValue(gameConfig, Map.class);
            if (Boolean.TRUE.equals(raw.get("mandatoryCapture"))) return "official";
            return Boolean.TRUE.equals(raw.get("seizure")) ? "seizure" : "casual";
        } catch (Exception e) {
            return "casual";
        }
    }

    /** The Traitors mode a room was set up with, when it's one of the built-in ones. */
    private static String traitorsModeOf(String gameConfig) {
        try {
            Object preset = gameConfig == null || gameConfig.isBlank() ? null
                    : JSON.readValue(gameConfig, Map.class).get("preset");
            return preset instanceof String slug && Presets.bySlug(slug) != null ? slug : null;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * The mode from the room's stored rules: Whot's "classic" or "tell",
     * SlayHuud's "battle" or "group"; null for games without one.
     */
    static String modeOf(String gameType, String gameConfig) {
        boolean slay = "slayhuud".equals(gameType);
        if ("truearena".equals(gameType)) return traitorsModeOf(gameConfig);
        if ("draughts".equals(gameType)) return draughtsModeOf(gameConfig);
        if (!"whot".equals(gameType) && !slay) return null;
        try {
            Object mode = gameConfig == null || gameConfig.isBlank() ? null : JSON.readValue(gameConfig, Map.class).get("mode");
            if (slay) return "group".equals(mode) ? "group" : "battle";
            return "tell".equals(mode) ? "tell" : "classic";
        } catch (Exception e) {
            return slay ? "battle" : "classic";
        }
    }

    private Mono<RoomView> addGameFresh(UUID host, UUID id, String gameType, Map<String, Object> config) {
        return requireHost(id, host)
                .filter(Space::live)
                .switchIfEmpty(Mono.error(ApiExceptions.conflict("Go Live first, then pick a game")))
                .flatMap(s -> championshipOn(s).flatMap(on -> on
                        ? Mono.<Space>error(ApiExceptions.conflict("The championship is on — finish it or call it off first"))
                        : putChampionshipAway(id).thenReturn(s)))
                .flatMap(s -> currentGame(s.currentRoomId()).flatMap(game -> {
                            if (!"finished".equals(game.status())) {
                                return Mono.error(ApiExceptions.conflict(
                                        "Finish the game that's on first, or put it away"));
                            }
                            return Mono.just(s);
                        }).defaultIfEmpty(s))
                .flatMap(s -> rooms.create(host, null, gameType, null, config, "chess".equals(gameType)
                        || ("draughts".equals(gameType) && config != null && Boolean.TRUE.equals(config.get("mandatoryCapture")))))
                .flatMap(room -> db.sql("UPDATE rooms SET huud_space_id=:id WHERE id=:room")
                        .bind("id", id).bind("room", room.id()).fetch().rowsUpdated()
                        .then(db.sql("UPDATE huud_spaces SET current_room_id=:room WHERE id=:id")
                                .bind("room", room.id()).bind("id", id).fetch().rowsUpdated())
                        .then(clearPlayQueue(id))
                        .thenReturn(room))
                .doOnSuccess(room -> notifyMembers(id, "game", host));
    }

    /** A championship taking registrations or being played — the Huud's one activity until it's done. */
    Mono<Boolean> championshipOn(Space s) {
        if (s.championshipId() == null) return Mono.just(false);
        return db.sql("SELECT status FROM championships WHERE id=:id").bind("id", s.championshipId())
                .map((r, m) -> r.get("status", String.class)).one()
                .map(status -> "lobby".equals(status) || "running".equals(status))
                .defaultIfEmpty(false);
    }

    /** Back to hanging out: the finished bracket stops showing (it stays in history). */
    Mono<Void> putChampionshipAway(UUID id) {
        return db.sql("UPDATE huud_spaces SET championship_id=NULL WHERE id=:id").bind("id", id).fetch().rowsUpdated().then();
    }

    /** Host only: put the current game away so another can be picked. A game in play can't be. */
    public Mono<HuudSpaceView> clearGame(UUID host, UUID id) {
        return requireHost(id, host)
                .flatMap(s -> currentGame(s.currentRoomId())
                        .flatMap(game -> "playing".equals(game.status())
                                ? Mono.error(ApiExceptions.conflict("The game is still being played"))
                                : cancelWaitingGame(s, host))
                        .then(db.sql("UPDATE huud_spaces SET current_room_id=NULL WHERE id=:id")
                                .bind("id", id).fetch().rowsUpdated())
                        .then(clearPlayQueue(id)))
                .doOnSuccess(n -> notifyMembers(id, "game", host))
                .then(view(id, host));
    }

    /** A new game, a new queue: nobody's old "can I play?" carries over. */
    private Mono<Void> clearPlayQueue(UUID id) {
        return db.sql("DELETE FROM huud_space_requests WHERE huud_space_id=:id AND kind='play'")
                .bind("id", id).fetch().rowsUpdated().then();
    }

    /** Availability is evaluated on every read, including stale invitation links. */
    public static String publicInviteSql(String s) {
        return "(" + s + ".status='active' AND " + s + ".live_since IS NOT NULL AND "
                + s + ".public_invite_host_id=" + s + ".owner_id AND EXISTS(SELECT 1 FROM rooms pi WHERE pi.id="
                + s + ".public_invite_room_id AND pi.id=" + s + ".current_room_id AND pi.status='lobby' "
                + "AND (SELECT count(*) FROM room_members pim WHERE pim.room_id=pi.id)<" + s + ".public_invite_seats))";
    }

    public Mono<HuudSpaceView> findPlayers(UUID host, UUID id) {
        return requireHost(id, host).filter(Space::live)
                .switchIfEmpty(Mono.error(ApiExceptions.conflict("Go live before inviting players")))
                .flatMap(s -> currentGame(s.currentRoomId())
                        .filter(g -> "waiting".equals(g.status()) && g.players() < g.seats())
                        .switchIfEmpty(Mono.error(ApiExceptions.conflict("Choose a game with a free seat first")))
                        .flatMap(g -> db.sql("UPDATE huud_spaces SET public_invite_room_id=:room, "
                                        + "public_invite_host_id=:host, public_invite_seats=:seats, "
                                        + "public_invite_at=CASE WHEN public_invite_room_id=:room THEN public_invite_at ELSE now() END WHERE id=:id")
                                .bind("room", g.roomId()).bind("host", host).bind("seats", g.seats()).bind("id", id)
                                .fetch().rowsUpdated()))
                .doOnSuccess(v -> notifyMembers(id, "game", host))
                .then(view(id, host));
    }

    public Mono<HuudSpaceView> stopFindingPlayers(UUID host, UUID id) {
        return requireHost(id, host)
                .then(db.sql("UPDATE huud_spaces SET public_invite_room_id=NULL, public_invite_at=NULL WHERE id=:id")
                        .bind("id", id).fetch().rowsUpdated())
                .doOnSuccess(v -> notifyMembers(id, "game", host))
                .then(view(id, host));
    }

    // ------------------------------------------------------------ the feed

    /** Host only: put the Huud on the feed, with an optional line like "Who wants to play Whot?". */
    public Mono<HuudSpaceView> share(UUID host, UUID id, String message) {
        String line = message == null || message.isBlank() ? null : message.strip().replaceAll("\\s+", " ");
        if (line != null && line.length() > 140) line = line.substring(0, 140).strip();
        String feedMessage = line;
        return requireHost(id, host)
                .flatMap(s -> {
                    var sql = db.sql("UPDATE huud_spaces SET shared_at=now(),feed_message=:message WHERE id=:id")
                            .bind("id", id);
                    return (feedMessage == null ? sql.bindNull("message", String.class) : sql.bind("message", feedMessage))
                            .fetch().rowsUpdated();
                })
                .then(view(id, host));
    }

    /** Host only: take it off the feed. */
    public Mono<HuudSpaceView> unshare(UUID host, UUID id) {
        return requireHost(id, host)
                .flatMap(s -> db.sql("UPDATE huud_spaces SET shared_at=NULL WHERE id=:id").bind("id", id).fetch().rowsUpdated())
                .then(view(id, host));
    }

    /**
     * A game nobody has started yet goes away with its stakes refunded. Asked
     * as the room's own host — after a hand-off that isn't the Huud's host.
     */
    Mono<Void> cancelWaitingGame(Space s, UUID by) {
        if (s.currentRoomId() == null) return Mono.empty();
        return currentGame(s.currentRoomId())
                .filter(game -> "waiting".equals(game.status()))
                .flatMap(game -> db.sql("SELECT host_id FROM rooms WHERE id=:id").bind("id", game.roomId())
                        .map((r, m) -> r.get("host_id", UUID.class)).one().defaultIfEmpty(by)
                        .flatMap(roomHost -> rooms.abandon(game.roomId(), roomHost)))
                .onErrorResume(e -> Mono.empty());
    }

    // ------------------------------------------------------------ reading

    public Mono<HuudSpaceView> view(UUID id, UUID viewer) {
        return view(id, viewer, true);
    }

    private Mono<HuudSpaceView> view(UUID id, UUID viewer, boolean enter) {
        return space(id)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("That Huud isn't here any more")))
                .flatMap(s -> membership(id, viewer).map(Optional::of).defaultIfEmpty(Optional.empty())
                        .flatMap(m -> {
                            boolean member = m.isPresent() && m.get().in() && s.active();
                            // Someone who asked to come in can see the door they're waiting at.
                            Mono<Boolean> allowed = m.isPresent() && !m.get().removed() && (m.get().in() || !s.active())
                                    ? Mono.just(true)
                                    : m.isPresent() && m.get().removed() ? Mono.just(false)
                                    : !s.active() ? Mono.just(false)
                                    : blocked(viewer, s.createdBy()).flatMap(b -> b ? Mono.just(false)
                                            : canSee(s, viewer).flatMap(see -> see ? Mono.just(true)
                                            : request(id, viewer, "join").map(r -> true).switchIfEmpty(request(id, viewer, "play").map(r -> true)).defaultIfEmpty(false)));
                            return allowed.flatMap(ok -> {
                                if (!ok) return Mono.error(ApiExceptions.forbidden("This Huud isn't open to you"));
                                // Opening a Live Huud you belong to is walking into the hangout.
                                Mono<Void> walkIn = enter && member && s.live() ? enterLive(id, viewer) : Mono.empty();
                                return walkIn.then(space(id)).flatMap(now -> membership(id, viewer)
                                        .map(Optional::of).defaultIfEmpty(Optional.empty())
                                        .flatMap(me -> Mono.zip(
                                                members(id).collectList(),
                                                currentGame(now.currentRoomId(), viewer).map(Optional::of).defaultIfEmpty(Optional.empty()),
                                                myRequests(id, viewer),
                                                pendingRequests(id).collectList(),
                                                watching(id),
                                                micApprovers(id).any(viewer::equals))
                                        .map(t -> {
                                            boolean host = now.active() && now.ownerId().equals(viewer);
                                            boolean owner = now.active() && now.createdBy().equals(viewer);
                                            boolean inLive = me.isPresent() && me.get().inLive() && now.live();
                                            List<Person> people = t.getT1();
                                            Person hostPerson = people.stream().filter(Person::host).findFirst()
                                                    .orElse(null);
                                            Map<String, String> mine = t.getT3();
                                            boolean canSpeak = now.live() && (host || (inLive && me.get().canSpeak()));
                                            CurrentGame game = t.getT2().map(g -> host || g.youArePlaying() ? g
                                                    : new CurrentGame(g.roomId(), null, g.gameType(), g.status(), g.players(),
                                                            g.seats(), g.playerIds(), false, g.readyIds(), g.table(),
                                                            g.mode())).orElse(null);
                                            int liveCount = (int) people.stream().filter(Person::here).count();
                                            return new HuudSpaceView(now.id(), member ? now.code() : null, now.name(), now.privacy(),
                                                    now.status(), hostPerson, people, game, member, host,
                                                    canSpeak, HuudSpaceAccess.VOICE_PREFIX + now.id(),
                                                    member ? null : mine.get("join"), mine.get("play"), mine.get("mic"),
                                                    t.getT4().stream().filter(request -> host || (t.getT6() && "mic".equals(request.kind()))).toList(), now.sharedAt() != null, now.feedMessage(), t.getT5(),
                                                    now.background(), now.createdAt(), now.endedAt(),
                                                    now.live(), owner, me.map(Membership::muted).orElse(false),
                                                    people.size(), liveCount, now.championshipId(), t.getT6(), now.findingPlayers());
                                        })));
                            });
                        }));
    }

    /** The Huud a game room belongs to, as the viewer sees it — empty for a room outside any Huud. */
    public Mono<HuudSpaceView> forRoom(UUID roomId, UUID viewer) {
        return db.sql("SELECT huud_space_id FROM rooms WHERE id=:id AND huud_space_id IS NOT NULL")
                .bind("id", roomId).map((r, m) -> r.get("huud_space_id", UUID.class)).one()
                .flatMap(id -> view(id, viewer));
    }

    /** Live Huuds you can look into: yours, your friends' and public ones. */
    public Flux<LiveHuud> live(UUID viewer) {
        return db.sql("SELECT s.id, s.name, s.privacy, s.created_at, r.game_type, r.status AS room_status, "
                        + CUP_COLUMNS + ", "
                        + "EXISTS(SELECT 1 FROM huud_space_members me WHERE me.huud_space_id=s.id AND me.user_id=:user AND me.left_at IS NULL) AS mine, "
                        + "(SELECT count(*) FROM huud_space_members c WHERE c.huud_space_id=s.id AND c.live_at IS NOT NULL) AS present, "
                        + watchingSql("s.id") + " AS watching, " + publicInviteSql("s") + " AS finding_players "
                        + "FROM huud_spaces s LEFT JOIN rooms r ON r.id=s.current_room_id " + CUP_JOIN
                        + "WHERE s.status='active' AND s.live_since IS NOT NULL "
                        + "AND NOT EXISTS(SELECT 1 FROM huud_space_members x WHERE x.huud_space_id=s.id AND x.user_id=:user AND x.removed) "
                        + "AND NOT " + blockedSql("s.created_by", ":user") + " "
                        + "AND EXISTS(SELECT 1 FROM huud_space_members p WHERE p.huud_space_id=s.id AND p.live_at IS NOT NULL) "
                        + "AND (s.privacy='public' OR " + publicInviteSql("s") + " "
                        + "  OR EXISTS(SELECT 1 FROM huud_space_members me WHERE me.huud_space_id=s.id AND me.user_id=:user AND me.left_at IS NULL) "
                        + "  OR EXISTS(SELECT 1 FROM huud_space_requests q WHERE q.huud_space_id=s.id AND q.user_id=:user AND q.kind='join' AND q.status='accepted') "
                        + "  OR (s.privacy='friends' AND EXISTS(SELECT 1 FROM friends f WHERE f.status='accepted' "
                        + "      AND f.low_user_id=LEAST(s.created_by,:user) AND f.high_user_id=GREATEST(s.created_by,:user)))) "
                        + "ORDER BY mine DESC, present DESC, s.created_at DESC LIMIT " + LIST_LIMIT)
                .bind("user", viewer)
                .map((r, m) -> new Object[]{r.get("id", UUID.class), r.get("name", String.class),
                        r.get("privacy", String.class), instant(r.get("created_at")), r.get("game_type", String.class),
                        r.get("room_status", String.class), Boolean.TRUE.equals(r.get("mine", Boolean.class)),
                        ((Number) r.get("present")).intValue(), ((Number) r.get("watching")).intValue(),
                        championshipLine(r.get("cup_name", String.class), r.get("cup_game", String.class),
                                r.get("cup_status", String.class), r.get("cup_size", Integer.class),
                                r.get("cup_round", Integer.class)), Boolean.TRUE.equals(r.get("finding_players", Boolean.class))})
                .all()
                .concatMap(row -> members((UUID) row[0]).collectList().map(people -> new LiveHuud(
                        (UUID) row[0], (String) row[1], (String) row[2],
                        people.stream().filter(Person::host).findFirst().orElse(null),
                        (int) row[7], people.stream().filter(Person::here).limit(6).toList(), (String) row[4],
                        row[5] == null ? null : gameStatus((String) row[5]), (boolean) row[6], (int) row[8],
                        (Instant) row[3], (HuudSpaceDtos.ChampionshipLine) row[9], (boolean) row[10])));
    }

    /**
     * The Huuds you belong to: your own first, then the ones that are Live,
     * then the rest by when they were last Live.
     */
    public Flux<MyHuud> mine(UUID viewer) {
        return db.sql("SELECT s.*, m.muted, r.game_type, r.status AS room_status, " + CUP_COLUMNS + " FROM huud_spaces s "
                        + "JOIN huud_space_members m ON m.huud_space_id=s.id LEFT JOIN rooms r ON r.id=s.current_room_id "
                        + CUP_JOIN
                        + "WHERE m.user_id=:user AND m.left_at IS NULL AND NOT m.removed AND s.status='active' "
                        + "ORDER BY (s.created_by=:user) DESC, (s.live_since IS NOT NULL) DESC, "
                        + "COALESCE(s.live_since, s.created_at) DESC LIMIT " + LIST_LIMIT)
                .bind("user", viewer).fetch().all()
                .concatMap(row -> {
                    Space s = toSpace(row);
                    return members(s.id()).collectList().map(people -> new MyHuud(s.id(), s.name(), s.privacy(), s.live(),
                            s.createdBy().equals(viewer), s.live() && s.ownerId().equals(viewer),
                            people.stream().filter(Person::host).findFirst().orElse(null), people.size(),
                            (int) people.stream().filter(Person::here).count(), people.stream().limit(6).toList(),
                            s.live() ? (String) row.get("game_type") : null,
                            s.live() && row.get("room_status") != null ? gameStatus((String) row.get("room_status")) : null,
                            s.background(), Boolean.TRUE.equals(row.get("muted")), s.liveSince(),
                            s.live() ? championshipLine((String) row.get("cup_name"), (String) row.get("cup_game"),
                                    (String) row.get("cup_status"), (Integer) row.get("cup_size"),
                                    (Integer) row.get("cup_round")) : null));
                });
    }

    /** The championship on in a Huud, for its card — finished ones count until the host puts them away. */
    private static final String CUP_COLUMNS = "cup.name AS cup_name, cup.game_type AS cup_game, cup.status AS cup_status, "
            + "cup.size AS cup_size, cup.current_round AS cup_round";
    private static final String CUP_JOIN = "LEFT JOIN championships cup ON cup.id=s.championship_id "
            + "AND cup.status IN ('lobby','running','completed') ";

    static HuudSpaceDtos.ChampionshipLine championshipLine(String name, String gameType, String status, Integer size,
                                                           Integer round) {
        if (name == null || status == null) return null;
        int rounds = size == null ? 3 : Integer.numberOfTrailingZeros(size);
        String roundName = "running".equals(status) && round != null && round > 0
                ? HuudChampionshipService.roundName(round, rounds) : null;
        return new HuudSpaceDtos.ChampionshipLine(name, gameType, HuudChampionshipService.status(status), roundName);
    }

    private Mono<Map<String, String>> myRequests(UUID id, UUID viewer) {
        return db.sql("SELECT kind, status FROM huud_space_requests WHERE huud_space_id=:id AND user_id=:user")
                .bind("id", id).bind("user", viewer)
                .map((r, m) -> Map.entry(r.get("kind", String.class), r.get("status", String.class))).all()
                .collectMap(Map.Entry::getKey, Map.Entry::getValue);
    }

    /** What the host has to answer, oldest first — only from people still around. */
    Flux<PendingRequest> pendingRequests(UUID id) {
        return db.sql("SELECT q.kind, q.created_at, u.id AS user_id, u.display_name, u.username, u.avatar_url, "
                        + "COALESCE(m.can_speak,false) AS can_speak "
                        + "FROM huud_space_requests q JOIN users u ON u.id=q.user_id "
                        + "LEFT JOIN huud_space_members m ON m.huud_space_id=q.huud_space_id AND m.user_id=q.user_id "
                        + "WHERE q.huud_space_id=:id AND q.status='pending' AND (m.removed IS NULL OR NOT m.removed) "
                        + "AND (q.kind='join' OR m.left_at IS NULL) ORDER BY q.created_at")
                .bind("id", id)
                .map((r, m) -> new PendingRequest(new Person(r.get("user_id", UUID.class),
                        r.get("display_name", String.class), r.get("username", String.class),
                        r.get("avatar_url", String.class), false, true,
                        Boolean.TRUE.equals(r.get("can_speak", Boolean.class)), null),
                        r.get("kind", String.class), instant(r.get("created_at"))))
                .all();
    }

    /**
     * The members: whoever's running it first, then the people in the Live
     * hangout, then everyone else in the order they joined.
     */
    Flux<Person> members(UUID id) {
        return db.sql("SELECT m.user_id, m.joined_at, (m.live_at IS NOT NULL AND s.live_since IS NOT NULL AND m.last_seen_at > now()-interval '75 seconds') AS here, "
                        + "(s.owner_id=m.user_id) AS host, (s.created_by=m.user_id) AS owner, "
                        + "(s.owner_id=m.user_id OR m.can_speak) AS can_speak, u.display_name, u.username, u.avatar_url, a.avatar_id, a.outfit_id "
                        + "FROM huud_space_members m JOIN users u ON u.id=m.user_id JOIN huud_spaces s ON s.id=m.huud_space_id LEFT JOIN user_huud_avatars a ON a.user_id=m.user_id "
                        + "WHERE m.huud_space_id=:id AND NOT m.removed AND m.left_at IS NULL "
                        + "ORDER BY (s.owner_id=m.user_id) DESC, (m.live_at IS NOT NULL) DESC, m.joined_at")
                .bind("id", id)
                .map((r, m) -> new Person(r.get("user_id", UUID.class), r.get("display_name", String.class),
                        r.get("username", String.class), r.get("avatar_url", String.class),
                        Boolean.TRUE.equals(r.get("host", Boolean.class)),
                        Boolean.TRUE.equals(r.get("here", Boolean.class)) && !inbox.isBackgrounded(r.get("user_id", UUID.class)),
                        Boolean.TRUE.equals(r.get("can_speak", Boolean.class)), instant(r.get("joined_at")),
                        Boolean.TRUE.equals(r.get("owner", Boolean.class)), r.get("avatar_id", String.class), r.get("outfit_id", String.class)))
                .all();
    }

    private Mono<CurrentGame> currentGame(UUID roomId) {
        return currentGame(roomId, null);
    }

    Mono<CurrentGame> currentGame(UUID roomId, UUID viewer) {
        if (roomId == null) return Mono.empty();
        return db.sql("SELECT r.id, r.code, r.game_type, r.status, r.game_config, "
                        + "ARRAY(SELECT rm.user_id FROM room_members rm WHERE rm.room_id=r.id ORDER BY rm.joined_at) AS players, "
                        + "ARRAY(SELECT rm.user_id FROM room_members rm WHERE rm.room_id=r.id AND rm.ready_state) AS ready "
                        + "FROM rooms r WHERE r.id=:id")
                .bind("id", roomId)
                .map((r, m) -> {
                    UUID[] players = r.get("players", UUID[].class);
                    UUID[] ready = r.get("ready", UUID[].class);
                    List<UUID> ids = players == null ? List.of() : List.of(players);
                    String type = r.get("game_type", String.class);
                    String mode = modeOf(type, r.get("game_config", String.class));
                    return new CurrentGame(r.get("id", UUID.class), r.get("code", String.class), type,
                            gameStatus(r.get("status", String.class)), ids.size(), seatsFor(type, mode),
                            ids, viewer != null && ids.contains(viewer), ready == null ? List.of() : List.of(ready),
                            List.<HuudSpaceDtos.Seat>of(), mode);
                })
                .one()
                .flatMap(game -> db.sql("SELECT u.id, u.display_name, u.avatar_url, u.is_bot, rm.ready_state "
                                + "FROM room_members rm JOIN users u ON u.id=rm.user_id WHERE rm.room_id=:id ORDER BY rm.joined_at")
                        .bind("id", game.roomId())
                        .map((r, m) -> new HuudSpaceDtos.Seat(r.get("id", UUID.class), r.get("display_name", String.class),
                                r.get("avatar_url", String.class), Boolean.TRUE.equals(r.get("is_bot", Boolean.class)),
                                Boolean.TRUE.equals(r.get("ready_state", Boolean.class))))
                        .all().collectList()
                        .map(table -> new CurrentGame(game.roomId(), game.code(), game.gameType(), game.status(),
                                game.players(), game.seats(), game.playerIds(), game.youArePlaying(), game.readyIds(), table,
                                game.mode())));
    }

    /** Words the app can show as they are: waiting → playing → finished. */
    public static String gameStatus(String roomStatus) {
        return switch (roomStatus) {
            case "lobby" -> "waiting";
            case "in_game" -> "playing";
            default -> "finished";
        };
    }

    // ------------------------------------------------------------ helpers

    Mono<Space> requireHost(UUID id, UUID user) {
        return space(id).filter(s -> s.active() && s.ownerId().equals(user))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("Only the host can do that")));
    }

    Mono<Space> space(UUID id) {
        return db.sql("SELECT s.*, " + publicInviteSql("s") + " AS finding_players FROM huud_spaces s WHERE s.id=:id").bind("id", id).fetch().one().map(HuudSpaceService::toSpace);
    }

    Mono<Membership> membership(UUID id, UUID user) {
        return db.sql("SELECT left_at, removed, can_speak, live_at, muted FROM huud_space_members "
                        + "WHERE huud_space_id=:id AND user_id=:user")
                .bind("id", id).bind("user", user)
                .map((r, m) -> new Membership(instant(r.get("left_at")), Boolean.TRUE.equals(r.get("removed", Boolean.class)),
                        Boolean.TRUE.equals(r.get("can_speak", Boolean.class)), instant(r.get("live_at")),
                        Boolean.TRUE.equals(r.get("muted", Boolean.class))))
                .one();
    }

    /** A member, or a clear "join first". */
    Mono<Space> requireMember(UUID id, UUID user) {
        return space(id).filter(Space::active)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("That Huud isn't here any more")))
                .flatMap(s -> membership(id, user).filter(Membership::in)
                        .switchIfEmpty(Mono.error(ApiExceptions.forbidden("Join the Huud first")))
                        .thenReturn(s));
    }

    private static Space toSpace(Map<String, Object> row) {
        return new Space((UUID) row.get("id"), (String) row.get("code"), (String) row.get("name"),
                (String) row.get("privacy"), (UUID) row.get("owner_id"), (UUID) row.get("created_by"),
                (String) row.get("status"), (UUID) row.get("current_room_id"),
                (String) row.get("feed_message"), instant(row.get("shared_at")), (String) row.get("background"),
                instant(row.get("live_since")), instant(row.get("created_at")), instant(row.get("ended_at")),
                (UUID) row.get("championship_id"), Boolean.TRUE.equals(row.get("finding_players")));
    }

    static Instant instant(Object value) {
        if (value == null) return null;
        if (value instanceof Instant i) return i;
        if (value instanceof OffsetDateTime o) return o.toInstant();
        if (value instanceof java.time.LocalDateTime l) return l.toInstant(java.time.ZoneOffset.UTC);
        throw new IllegalStateException("unexpected timestamp " + value.getClass());
    }

    /**
     * Off the Huud's voice — its own room and any championship match room —
     * best effort: LiveKit being down mustn't stop a removal.
     */
    private Mono<Void> dropFromVoice(UUID id, UUID user) {
        return access.voiceRooms(id).concatMap(room -> voice.remove(room, user.toString()).onErrorResume(e -> Mono.empty())

                        .then(voiceSessions.removeMembership(user, room).onErrorResume(e -> Mono.empty())))
                .then(dropUserPreviews(id, user));
    }

    Mono<Void> lock(String key) {
        return db.sql("SELECT 1 AS locked FROM pg_advisory_xact_lock(hashtextextended(:key,0))")
                .bind("key", key).fetch().all().then();
    }

    /** Everyone in the Huud refreshes it — what changed is in {@code event}. */
    void notifyMembers(UUID id, String event, UUID by) {
        members(id).subscribe(p -> notify(p.userId(), id, event, by), e -> { });
    }

    void notify(UUID user, UUID id, String event, UUID by) {
        inbox.notify(user, Map.of("type", "HUUD_SPACE",
                "data", Map.of("huudSpaceId", id.toString(), "event", event, "by", by.toString())));
        if (PUSHED.containsKey(event)) pushWhenAway(user, id, event, by);
    }

    /** What reaches a phone in someone's pocket, with {by} and {huud} filled in. */
    static final Map<String, String> PUSHED = Map.of(
            "invited", "{by} invited you to {huud} 🎉",
            "request", "{by} is asking you something in {huud} ✋",
            "accepted-join", "You're in {huud}! 🎉",
            "accepted-play", "You're in the game in {huud}! 🎮",
            "accepted-mic", "You can talk in {huud} now 🎙️",
            "picked", "{by} picked you to play in {huud}! Tap to jump in 🎮",
            "championship-match", "Your championship match in {huud} is ready — tap to play 🏆");
    // "live" is pushed by announceLive, which knows the game and the host's choice.

    private void pushWhenAway(UUID user, UUID id, String event, UUID by) {
        if (push == null) return;
        db.sql("SELECT (SELECT display_name FROM users WHERE id=:by) AS by_name, name FROM huud_spaces WHERE id=:id")
                .bind("by", by).bind("id", id)
                .map((r, m) -> PUSHED.get(event)
                        .replace("{by}", String.valueOf(r.get("by_name", String.class)).split(" ")[0])
                        .replace("{huud}", r.get("name", String.class)))
                .one()
                .subscribe(text -> push.sendToUserIfOffline(user, "PlayHuud", text,
                        Map.of("type", "HUUD_SPACE", "huudSpaceId", id.toString(), "event", event)), e -> { });
    }
}
