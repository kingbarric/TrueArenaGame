package app.truearena.api.room;

import app.truearena.api.auth.JwtService;
import app.truearena.api.coins.CoinService;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.room.RoomDtos.DiscoverableRoomView;
import app.truearena.api.room.RoomDtos.RoomMemberView;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.room.RoomRuntime;
import app.truearena.room.RoomRuntimeRegistry;
import org.springframework.stereotype.Service;
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
    private static final SecureRandom RNG = new SecureRandom();

    private final RoomRepository rooms;
    private final RoomMemberRepository members;
    private final UserRepository users;
    private final JwtService jwt;
    private final InboxRegistry inbox;
    private final FriendRepository friends;
    private final RoomRuntimeRegistry runtimes;
    private final CoinService coins;

    public RoomService(RoomRepository rooms, RoomMemberRepository members, UserRepository users, JwtService jwt,
                        InboxRegistry inbox, FriendRepository friends, RoomRuntimeRegistry runtimes, CoinService coins) {
        this.friends = friends;
        this.runtimes = runtimes;
        this.rooms = rooms;
        this.members = members;
        this.users = users;
        this.jwt = jwt;
        this.inbox = inbox;
        this.coins = coins;
    }

    private static final java.util.Set<String> GAME_TYPES = java.util.Set.of("truearena", "wordbluff", "draughts", "goosi", "whot");

    /** A guest can join any room, but hosting (creating) one needs a real
     * account — otherwise there's no way to reach them again if the app is
     * reinstalled, and no one to hand the room off to if they leave. The
     * Flutter client also gates this in the UI (a friendlier prompt before
     * the request is even sent), but this is the actual enforcement. */
    public Mono<RoomView> create(UUID hostId, UUID groupId, String gameType, Long stake,
                                 java.util.Map<String, Object> gameConfig) {
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
                                        writeConfig(gameConfig))))
                                .flatMap(room -> members.save(RoomMemberRow.of(room.id(), hostId, null)).thenReturn(room))
                                .flatMap(room -> escrowStake(room, hostId))
                                .doOnNext(room -> notifyCallCompanions(room, host.displayName()))
                                .flatMap(room -> view(room, hostId)));
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
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no room with that code")))
                .flatMap(room -> members.findByRoomIdAndUserId(room.id(), userId)
                        .flatMap(existing -> view(room, userId))
                        .switchIfEmpty(members.countByRoomId(room.id())
                                .flatMap(count -> count >= MAX_PLAYERS
                                        ? Mono.error(ApiExceptions.conflict("room is full"))
                                        : members.save(RoomMemberRow.of(room.id(), userId, nickname))
                                        .thenReturn(room)
                                        .flatMap(r -> escrowStake(r, userId))
                                        .then(view(room, userId)))));
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
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("room not found")))
                .flatMap(room -> {
                    if (!room.hostId().equals(callerId)) {
                        return Mono.error(ApiExceptions.forbidden("only the host can abandon this room"));
                    }
                    boolean started = runtimes.find(roomId).map(RoomRuntime::started).orElse(false);
                    if (started) {
                        return Mono.error(ApiExceptions.conflict("the game has already started — forfeit instead"));
                    }
                    return refundStakes(room).then(members.deleteByRoomId(roomId)).then(rooms.deleteById(roomId));
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
                            .concatMap(this::discoverableView);
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
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("room not found")))
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
                        list, "/ws/room/" + room.id(), jwt.issueAccess(viewerId)));
    }

    private Mono<String> allocateCode(int attemptsLeft) {
        String candidate = randomCode();
        return rooms.findByCode(candidate)
                .flatMap(existing -> attemptsLeft > 0
                        ? allocateCode(attemptsLeft - 1)
                        : Mono.<String>error(ApiExceptions.conflict("could not allocate a room code")))
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
