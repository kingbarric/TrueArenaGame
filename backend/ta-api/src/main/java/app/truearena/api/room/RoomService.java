package app.truearena.api.room;

import app.truearena.api.auth.JwtService;
import app.truearena.api.bot.BotRuntimeRegistry;
import app.truearena.api.championship.ChampionshipService;
import app.truearena.api.coins.CoinService;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.room.RoomDtos.DiscoverableRoomView;
import app.truearena.api.room.RoomDtos.RoomMemberView;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.support.ApiExceptions;
import app.truearena.api.ws.GameOrchestrator;
import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.room.RoomRuntime;
import app.truearena.room.RoomRuntimeRegistry;
import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Autowired;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.security.SecureRandom;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class RoomService {

    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no O/0/I/1
    private static final int MAX_PLAYERS = 16;

    /** Join refused because the game is live — the app turns this into "watch live". Keep in step with `kAlreadyPlaying` in the app. */
    public static final String ALREADY_PLAYING = "this huud is already playing — watch live instead";
    private static final SecureRandom RNG = new SecureRandom();

    private final RoomRepository rooms;
    private final RoomMemberRepository members;
    private final UserRepository users;
    private final JwtService jwt;
    private final InboxRegistry inbox;
    private final FriendRepository friends;
    private final RoomRuntimeRegistry runtimes;
    private final CoinService coins;
    private final BotRuntimeRegistry botRuntimes;
    private final GameOrchestrator games;
    @Autowired(required = false)
    private ChampionshipService championships;

    public RoomService(RoomRepository rooms, RoomMemberRepository members, UserRepository users, JwtService jwt,
                        InboxRegistry inbox, FriendRepository friends, RoomRuntimeRegistry runtimes, CoinService coins,
                        BotRuntimeRegistry botRuntimes, GameOrchestrator games) {
        this.friends = friends;
        this.runtimes = runtimes;
        this.rooms = rooms;
        this.members = members;
        this.users = users;
        this.jwt = jwt;
        this.inbox = inbox;
        this.coins = coins;
        this.botRuntimes = botRuntimes;
        this.games = games;
    }

    private static final java.util.Set<String> GAME_TYPES = java.util.Set.of("truearena", "wordbluff", "draughts", "goosi", "whot", "ludo", "chess");

    /** A guest can join any room, but hosting (creating) one needs a real
     * account — otherwise there's no way to reach them again if the app is
     * reinstalled, and no one to hand the room off to if they leave. The
     * Flutter client also gates this in the UI (a friendlier prompt before
     * the request is even sent), but this is the actual enforcement. */
    public Mono<RoomView> create(UUID hostId, UUID groupId, String gameType, Long stake,
                                 java.util.Map<String, Object> gameConfig) {
        return create(hostId, groupId, gameType, stake, gameConfig, false);
    }

    /**
     * {@code ranked} is the host's request for a rated match, nothing more:
     * whether the finished game actually moves anyone's rating is decided
     * server-side at the end (see {@code RatedMatchPolicy}).
     */
    public Mono<RoomView> create(UUID hostId, UUID groupId, String gameType, Long stake,
                                 java.util.Map<String, Object> gameConfig, boolean ranked) {
        String type = gameType == null || gameType.isBlank() ? "truearena" : gameType;
        if (!GAME_TYPES.contains(type)) {
            return Mono.error(ApiExceptions.badRequest("unknown gameType: " + type));
        }
        // Staking is opt-in per room, never required — a null/omitted stake
        // (the common case) is a perfectly ordinary unstaked room.
        long stakeCoins = stake == null ? 0 : stake;
        if (stakeCoins < 0) {
            return Mono.error(ApiExceptions.badRequest("stake can't be negative"));
        }
        return users.findById(hostId)
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("unknown user")))
                .flatMap(host -> host.isGuest()
                        ? Mono.error(ApiExceptions.forbidden("verify a phone or email to host a game — guests can join, not host"))
                        : allocateCode(5)
                                .flatMap(code -> rooms.save(RoomRow.create(code, groupId, hostId, type, stakeCoins,
                                        writeConfig(ranked ? withRankedRules(type, gameConfig) : gameConfig), ranked)))
                                .flatMap(room -> members.save(RoomMemberRow.of(room.id(), hostId, host.username())).thenReturn(room))
                                .flatMap(room -> escrowStake(room, hostId))
                                .doOnNext(room -> notifyCallCompanions(room, host.displayName()))
                                .flatMap(room -> view(room, hostId)));
    }

    /**
     * Rules every rated game of a type is played under, whatever the client
     * sent — a rating earned under house rules wouldn't mean the same thing,
     * and the app's locked toggle is only a convenience, not the guarantee.
     */
    static final Map<String, Map<String, Object>> RANKED_RULES = Map.of(
            "draughts", Map.of("mandatoryCapture", true));

    static java.util.Map<String, Object> withRankedRules(String gameType, java.util.Map<String, Object> requested) {
        Map<String, Object> rules = RANKED_RULES.get(gameType);
        if (rules == null) {
            return requested;
        }
        java.util.Map<String, Object> merged = new java.util.HashMap<>(requested == null ? Map.of() : requested);
        merged.putAll(rules);
        return merged;
    }

    /** Host-chosen options, stored as JSON. Unreadable input is dropped rather than failing room creation. */
    private String writeConfig(java.util.Map<String, Object> gameConfig) {
        if (gameConfig == null || gameConfig.isEmpty()) {
            return null;
        }
        try {
            return new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(gameConfig);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Debits the stake from whoever just joined (host at creation, or any
     * later joiner) — on failure the just-added membership (and the room
     * itself, if they were its only member) is rolled back, so a declined
     * stake never leaves a half-joined room sitting around. A no-op for an
     * unstaked room.
     */
    private Mono<RoomRow> escrowStake(RoomRow room, UUID userId) {
        if (room.stakeCoins() <= 0) {
            return Mono.just(room);
        }
        return coins.debit(userId, room.stakeCoins(), CoinService.REASON_MATCH_STAKE_ESCROW, room.id())
                .thenReturn(room)
                .onErrorResume(err -> members.deleteByRoomIdAndUserId(room.id(), userId)
                        .then(members.countByRoomId(room.id()))
                        .flatMap(count -> count == 0 ? rooms.deleteById(room.id()) : Mono.empty())
                        .then(Mono.error(ApiExceptions.conflict(
                                "not enough coins to stake " + room.stakeCoins()))));
    }

    /**
     * "Someone spun up a game — everyone on the call gets a Join
     * notification" (see {@code InboxRegistry}). Best-effort and silent if
     * nobody's on a call with the host, or nobody's inbox is connected —
     * this is a nice-to-have layered on top of room creation, never a
     * reason for it to fail.
     */
    private void notifyCallCompanions(RoomRow room, String hostName) {
        for (UUID companion : inbox.callCompanionsOf(room.hostId())) {
            inbox.notify(companion, Map.of(
                    "type", "GAME_STARTING",
                    "data", Map.of(
                            "roomId", room.id().toString(),
                            "roomCode", room.code(),
                            "gameType", room.gameType(),
                            "hostName", hostName)));
        }
    }

    public Mono<RoomView> join(String code, UUID userId, String nickname) {
        return rooms.findByCode(code.toUpperCase())
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no huud with that code")))
                .flatMap(room -> (championships == null ? Mono.just(false) : championships.isTournamentRoom(room.id()))
                        .flatMap(tournament -> tournament
                                ? Mono.error(ApiExceptions.forbidden("join the championship invitation instead"))
                                : members.findByRoomIdAndUserId(room.id(), userId)
                        .flatMap(existing -> view(room, userId))
                        .switchIfEmpty("in_game".equals(room.status())
                                // The app matches on ALREADY_PLAYING and takes the person
                                // to the live view instead of showing an error.
                                ? Mono.error(ApiExceptions.conflict(ALREADY_PLAYING))
                                : "ended".equals(room.status())
                                // A finished huud used to get the "already playing" message too,
                                // which sent people to watch something that wasn't live.
                                ? Mono.error(ApiExceptions.conflict("this huud has already ended"))
                                : members.countByRoomId(room.id())
                                .flatMap(count -> count >= ("ludo".equals(room.gameType()) ? 4 : MAX_PLAYERS)
                                        ? Mono.error(ApiExceptions.conflict("huud is full"))
                                        : resolvedNickname(userId, nickname)
                                        .flatMap(resolved -> members.save(RoomMemberRow.of(room.id(), userId, resolved)))
                                        .thenReturn(room)
                                        .flatMap(r -> escrowStake(r, userId))
                                        .then(view(room, userId))))));
    }

    public Mono<RoomView> watch(String code, UUID userId) {
        return rooms.findByCode(code.toUpperCase())
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no huud with that code")))
                .filter(room -> "in_game".equals(room.status()))
                .switchIfEmpty(Mono.error(ApiExceptions.conflict("this huud is not live yet")))
                .flatMap(room -> (championships == null ? Mono.just(true)
                        : championships.spectatorAllowed(room.id(), userId))
                        .flatMap(allowed -> allowed ? view(room, userId)
                                : Mono.error(ApiExceptions.forbidden("private championship match"))));
    }

    /** A room member's display name defaults to their username, not their
     * full real name — a huud code is sometimes shared outside your circle
     * of friends, and a username is the handle you'd want strangers to see. */
    private Mono<String> resolvedNickname(UUID userId, String nickname) {
        if (nickname != null && !nickname.isBlank()) {
            return Mono.just(nickname);
        }
        return users.findById(userId).map(UserRow::username).defaultIfEmpty("player");
    }

    /**
     * Leave a lobby before the game starts — refunds every staked member's
     * escrow and deletes the room. Only the host can call this, and only
     * while nothing's actually running yet (no live runtime, or one that
     * exists but never started); once a game is underway this is refused —
     * that's what forfeit/quitting mid-game is for, and it settles the
     * stake through the normal win/loss payout instead of a refund.
     */
    public Mono<Void> abandon(UUID roomId, UUID callerId) {
        return rooms.findById(roomId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("huud not found")))
                .flatMap(room -> (championships == null ? Mono.just(false) : championships.isTournamentRoom(roomId))
                        .flatMap(tournament -> {
                    if (tournament) return Mono.error(ApiExceptions.forbidden("championship matches cannot be abandoned"));
                    if (!room.hostId().equals(callerId)) {
                        return Mono.error(ApiExceptions.forbidden("only the host can abandon this huud"));
                    }
                    boolean started = runtimes.find(roomId).map(RoomRuntime::started).orElse(false);
                    if (started) {
                        return Mono.error(ApiExceptions.conflict("the game has already started — forfeit instead"));
                    }
                    return members.findByRoomId(roomId).map(RoomMemberRow::userId).collectList()
                            .flatMap(ids -> refundStakes(room)
                                    .then(members.deleteByRoomId(roomId))
                                    .then(rooms.deleteById(roomId))
                                    .doOnSuccess(ignored -> {
                                        botRuntimes.stopRoom(roomId);
                                        runtimes.find(roomId).ifPresent(RoomRuntime::cancelTimer);
                                        runtimes.remove(roomId);
                                    }));
                }));
    }

    /** Leaving a private Draughts or Chess game against a system agent ends that room. */
    public Mono<Boolean> leaveBotDraughtsRoom(UUID roomId, UUID callerId) {
        return rooms.findById(roomId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("huud not found")))
                .flatMap(room -> {
                    if (!java.util.Set.of("draughts", "chess").contains(room.gameType()) || !room.hostId().equals(callerId)
                            || "ended".equals(room.status())) {
                        return Mono.just(false);
                    }
                    return (championships == null ? Mono.just(false) : championships.isTournamentRoom(roomId))
                            .flatMap(tournament -> tournament ? Mono.just(false)
                                    : members.findByRoomId(roomId).collectList().flatMap(roster -> {
                                        if (roster.size() != 2 || roster.stream().noneMatch(m -> m.userId().equals(callerId))) {
                                            return Mono.just(false);
                                        }
                                        UUID opponentId = roster.stream().filter(m -> !m.userId().equals(callerId))
                                                .findFirst().orElseThrow().userId();
                                        return users.findById(opponentId).flatMap(opponent -> {
                                            if (!opponent.isBot()) {
                                                return Mono.just(false);
                                            }
                                            Mono<Boolean> end = "lobby".equals(room.status())
                                                    ? abandon(roomId, callerId).thenReturn(true)
                                                    : games.forfeitBotDraughtsRoom(roomId, callerId)
                                                            .flatMap(forfeited -> forfeited ? Mono.just(true)
                                                                    : refundStakes(room)
                                                                            .then(rooms.save(room.withStatus("ended")))
                                                                            .thenReturn(true));
                                            return end.doOnSuccess(ended -> {
                                                if (ended) {
                                                    botRuntimes.stopRoom(roomId);
                                                    runtimes.find(roomId).ifPresent(RoomRuntime::cancelTimer);
                                                    runtimes.remove(roomId);
                                                }
                                            });
                                        });
                                    }));
                });
    }

    /** Close a Whot table when the host leaves only Cyber Agents behind. */
    public Mono<Boolean> leaveBotWhotRoom(UUID roomId, UUID callerId) {
        return leaveBotRoom(roomId, callerId, "whot");
    }

    public Mono<Boolean> leaveBotLudoRoom(UUID roomId, UUID callerId) {
        return leaveBotRoom(roomId, callerId, "ludo");
    }

    /** Close an Oware pit when the host leaves only Cyber Agents behind. */
    public Mono<Boolean> leaveBotGoosiRoom(UUID roomId, UUID callerId) {
        return leaveBotRoom(roomId, callerId, "goosi");
    }

    /** Close a Word Bluff table when the host leaves only Cyber Agents behind. */
    public Mono<Boolean> leaveBotWordBluffRoom(UUID roomId, UUID callerId) {
        return leaveBotRoom(roomId, callerId, "wordbluff");
    }

    public Mono<Boolean> leaveLudoRoom(UUID roomId, UUID callerId) {
        return members.findByRoomIdAndUserId(roomId, callerId)
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("not a player in this huud")))
                .then(leaveBotLudoRoom(roomId, callerId))
                .flatMap(ended -> ended ? Mono.just(true) : games.forfeitLudoRoom(roomId, callerId));
    }

    private Mono<Boolean> forfeitBotRoomFor(String gameType, UUID roomId, UUID callerId) {
        return switch (gameType) {
            case "ludo" -> games.forfeitLudoRoom(roomId, callerId);
            case "whot" -> games.forfeitBotWhotRoom(roomId, callerId);
            case "goosi" -> games.forfeitBotGoosiRoom(roomId, callerId);
            case "wordbluff" -> games.forfeitBotWordBluffRoom(roomId, callerId);
            default -> Mono.just(false);
        };
    }

    private Mono<Boolean> leaveBotRoom(UUID roomId, UUID callerId, String gameType) {
        return rooms.findById(roomId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("huud not found")))
                .flatMap(room -> {
                    if (!gameType.equals(room.gameType()) || !room.hostId().equals(callerId)
                            || "ended".equals(room.status())) {
                        return Mono.just(false);
                    }
                    return members.findByRoomId(roomId).collectList().flatMap(roster -> {
                        if (roster.size() < 2 || roster.stream().noneMatch(m -> m.userId().equals(callerId))) {
                            return Mono.just(false);
                        }
                        var agentIds = roster.stream().map(RoomMemberRow::userId)
                                .filter(id -> !id.equals(callerId)).toList();
                        return Flux.fromIterable(agentIds)
                                .concatMap(id -> users.findById(id)
                                        .map(user -> user.isBot())
                                        .defaultIfEmpty(false))
                                .all(Boolean::booleanValue)
                                .flatMap(allAgents -> {
                                    if (!allAgents) return Mono.just(false);
                                    Mono<Boolean> end = "lobby".equals(room.status())
                                            ? abandon(roomId, callerId).thenReturn(true)
                                            : forfeitBotRoomFor(gameType, roomId, callerId)
                                                    .flatMap(forfeited -> forfeited
                                                            && (!"ludo".equals(gameType) || runtimes.find(roomId)
                                                            .map(rt -> rt.state().finished()).orElse(false))
                                                            ? Mono.just(true) : refundStakes(room)
                                                                    .then(rooms.save(room.withStatus("ended")))
                                                                    .thenReturn(true));
                                    return end.doOnSuccess(ended -> {
                                        if (ended) {
                                            botRuntimes.stopRoom(roomId);
                                            runtimes.find(roomId).ifPresent(RoomRuntime::cancelTimer);
                                            runtimes.remove(roomId);
                                        }
                                    });
                                });
                    });
                });
    }

    private Mono<Void> refundStakes(RoomRow room) {
        if (room.stakeCoins() <= 0) {
            return Mono.empty();
        }
        return members.findByRoomId(room.id())
                .flatMap(m -> coins.credit(m.userId(), room.stakeCoins(), CoinService.REASON_MATCH_STAKE_REFUND, room.id())
                        .onErrorResume(err -> Mono.empty())) // best-effort — never blocks the room from being torn down
                .then();
    }

    /**
     * Rooms you can spectate right now: a friend's game that's actually
     * started (not just sitting in the lobby), sourced from the live
     * in-memory runtimes on this pod (v1, single-pod scope — same as
     * everywhere else runtimes are read directly). Joining as a spectator
     * is then just {@code GET /rooms/{id}} for a session token, same as any
     * other room lookup — {@code get()} never gates on membership.
     */
    public Flux<DiscoverableRoomView> discoverable(UUID selfId) {
        return friends.findByLowUserIdOrHighUserId(selfId, selfId)
                .filter(row -> FriendRow.ACCEPTED.equals(row.status()))
                .map(row -> row.otherUser(selfId))
                .collect(Collectors.toSet())
                .flatMapMany(friendIds -> {
                    Set<UUID> hosts = runtimes.all().stream()
                            .filter(RoomRuntime::started)
                            .map(rt -> UUID.fromString(rt.hostUserId))
                            .filter(friendIds::contains)
                            .collect(Collectors.toSet());
                    return Flux.fromIterable(runtimes.all())
                            .filter(RoomRuntime::started)
                            .filter(rt -> hosts.contains(UUID.fromString(rt.hostUserId)))
                            .concatMap(rt -> championships == null ? discoverableView(rt)
                                    : championships.spectatorAllowed(rt.roomId, selfId)
                                            .flatMapMany(allowed -> allowed ? discoverableView(rt) : Flux.empty()));
                });
    }

    private Mono<DiscoverableRoomView> discoverableView(RoomRuntime rt) {
        return rooms.findById(rt.roomId)
                .flatMap(room -> users.findById(room.hostId())
                        .map(host -> new DiscoverableRoomView(
                                room.id(), room.code(), room.gameType(), host.displayName(), rt.connectedUserIds.size()))
                        .defaultIfEmpty(new DiscoverableRoomView(
                                room.id(), room.code(), room.gameType(), "Someone", rt.connectedUserIds.size())));
    }

    public Mono<RoomView> get(UUID roomId, UUID userId) {
        return rooms.findById(roomId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("huud not found")))
                .flatMap(room -> (championships == null ? Mono.just(true)
                        : championships.spectatorAllowed(roomId, userId))
                        .flatMap(allowed -> allowed ? view(room, userId)
                                : Mono.error(ApiExceptions.forbidden("private championship match"))));
    }

    /** Recover a player's latest live room after reinstall or an older client. */
    public Mono<RoomView> mostRecentActive(UUID userId) {
        return rooms.findRecentActiveForUser(userId)
                .next()
                .flatMap(room -> view(room, userId));
    }

    private Mono<RoomView> view(RoomRow room, UUID viewerId) {
        return members.findByRoomId(room.id())
                .concatMap(m -> users.findById(m.userId())
                        .map(u -> new RoomMemberView(m.userId(), m.nickname(), m.connectionStatus(),
                                m.readyState(), u.isBot(), u.avatarUrl()))
                        .defaultIfEmpty(new RoomMemberView(m.userId(), m.nickname(), m.connectionStatus(),
                                m.readyState(), false, null)))
                .collectList()
                .map(list -> new RoomView(
                        room.id(), room.code(), room.groupId(), room.hostId(), room.status(), room.gameType(),
                        room.stakeCoins(), room.createdAt(),
                        list, "/ws/room/" + room.id(), jwt.issueAccess(viewerId), room.ranked()));
    }

    private Mono<String> allocateCode(int attemptsLeft) {
        String candidate = randomCode();
        return rooms.findByCode(candidate)
                .flatMap(existing -> attemptsLeft > 0
                        ? allocateCode(attemptsLeft - 1)
                        : Mono.<String>error(ApiExceptions.conflict("could not allocate a huud code")))
                .switchIfEmpty(Mono.just(candidate));
    }

    private static String randomCode() {
        StringBuilder sb = new StringBuilder(6);
        for (int i = 0; i < 6; i++) {
            sb.append(ALPHABET.charAt(RNG.nextInt(ALPHABET.length())));
        }
        return sb.toString();
    }
}
