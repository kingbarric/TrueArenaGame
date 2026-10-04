package app.truearena.api.bot;

import app.truearena.api.auth.JwtService;
import app.truearena.api.auth.UsernameGenerator;
import app.truearena.api.bot.BotDtos.BotAddedView;
import app.truearena.api.coins.CoinService;
import app.truearena.api.championship.ChampionshipService;
import app.truearena.api.room.RoomService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.room.RoomLock;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.net.URI;
import java.time.Duration;
import java.util.UUID;

/**
 * Adding a bot is host-only, lobby-only (see {@link #addBot}) — a bot is a
 * real {@code users} row (see {@code UserRow.newBot}) and a real
 * {@code room_members} row, so everything downstream (roster display,
 * `GameOrchestrator.initialState` player list, stats) treats it exactly
 * like a human player without any special-casing.
 */
@Service
public class BotService {

    private final RoomRepository rooms;
    private final RoomMemberRepository members;
    private final UserRepository users;
    private final UsernameGenerator usernames;
    private final JwtService jwt;
    private final ObjectMapper mapper;
    private final GameBotAdapterFactory adapters;
    private final LlmMovePicker picker;
    private final BotRuntimeRegistry registry;
    private final CoinService coins;
    private final RoomLock agentLock;
    @Autowired(required = false)
    private ChampionshipService championships;
    @Autowired(required = false)
    private RoomService roomService;

    /** A soft throttle so a room can't be filled with free bots without limit — see docs/DEV_REFERENCE.md. */
    private static final long BOT_COST = 20;
    private static final long MAX_AGENTS = 5;

    @Value("${server.port:8080}")
    private int serverPort;

    public BotService(RoomRepository rooms, RoomMemberRepository members, UserRepository users,
                       UsernameGenerator usernames, JwtService jwt, ObjectMapper mapper,
                       GameBotAdapterFactory adapters, LlmMovePicker picker, BotRuntimeRegistry registry,
                       CoinService coins, RoomLock agentLock) {
        this.rooms = rooms;
        this.members = members;
        this.users = users;
        this.usernames = usernames;
        this.jwt = jwt;
        this.mapper = mapper;
        this.adapters = adapters;
        this.picker = picker;
        this.registry = registry;
        this.coins = coins;
        this.agentLock = agentLock;
    }

    /** One roster of agent identities, usable in every game with a bot adapter. */
    public Flux<BotAddedView> listAgents(UUID ownerId, String gameType) {
        return users.findAgentsOf(ownerId).map(BotService::toView);
    }

    /**
     * Retires an agent for good. The bot's {@code users} row is the agent,
     * so deleting it is the deletion — room_members cascades off it.
     *
     * <p>Refused while the agent is in a room that hasn't ended: pulling a
     * player off a live board would strand whoever is still sitting at it.
     */
    public Mono<Void> deleteAgent(UUID agentId, UUID requesterId) {
        return users.findById(agentId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such agent")))
                .flatMap(agent -> {
                    if (!agent.isBot() || !requesterId.equals(agent.ownerUserId())) {
                        return Mono.error(ApiExceptions.forbidden("not your agent"));
                    }
                    return releaseAbandonedAgentRooms(agentId, requesterId)
                            .then(members.countLiveRoomsFor(agentId))
                            .defaultIfEmpty(0L)
                            .flatMap(live -> live > 0
                                    ? Mono.error(ApiExceptions.conflict("that agent is still in a game"))
                                    : Mono.fromRunnable(() -> registry.stop(agentId))
                                            // Older builds could leave an agent holding an
                                            // ended room; hand those back to its owner so
                                            // the row is free to go.
                                            .then(rooms.reassignHost(agentId, requesterId))
                                            .then(users.deleteById(agentId)));
                });
    }

    /** Renaming is just a display-name edit — the agent keeps its id, so rooms it's in are unaffected. */
    public Mono<BotAddedView> rename(UUID agentId, UUID requesterId, String newName) {
        return users.findById(agentId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such agent")))
                .flatMap(agent -> {
                    if (!agent.isBot() || !requesterId.equals(agent.ownerUserId())) {
                        return Mono.error(ApiExceptions.forbidden("not your agent"));
                    }
                    return users.save(agent.renamed(newName)).map(BotService::toView);
                });
    }

    /**
     * Puts an agent the caller already created into this room — free. The
     * fee is charged once, when the agent is made; charging it again every
     * game made playing an agent cost more than beating one pays, which is
     * how players kept ending up unable to afford an opponent at all.
     */
    public Mono<BotAddedView> addExistingAgent(UUID roomId, UUID requesterId, UUID agentId) {
        return hostedLobby(roomId, requesterId)
                .flatMap(room -> users.findById(agentId)
                        .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such agent")))
                        .flatMap(agent -> {
                            if (!agent.isBot() || !requesterId.equals(agent.ownerUserId())) {
                                return Mono.error(ApiExceptions.forbidden("not your agent"));
                            }
                            if (adapters.create(room.gameType()) == null) {
                                return Mono.error(ApiExceptions.badRequest("bots don't support " + room.gameType() + " yet"));
                            }
                            return members.countByRoomId(roomId).flatMap(seats -> {
                                if ("ludo".equals(room.gameType()) && seats >= 4) {
                                    return Mono.error(ApiExceptions.conflict("Ludo has four seats"));
                                }
                                return agentLock.withLock(requesterId, Duration.ofSeconds(30),
                                        () -> attachExistingAgent(room, requesterId, agent));
                            });
                        }));
    }

    private Mono<BotAddedView> attachExistingAgent(RoomRow room, UUID requesterId, UserRow agent) {
        UUID roomId = room.id();
        UUID agentId = agent.id();
        return members.findByRoomIdAndUserId(roomId, agentId)
                .flatMap(existing -> Mono.<BotAddedView>error(
                        ApiExceptions.conflict("that agent is already in this huud")))
                .switchIfEmpty(Mono.defer(() -> releaseAbandonedAgentRooms(agentId, requesterId)
                        .then(members.countLiveRoomsFor(agentId))
                        .flatMap(live -> live > 0
                                ? Mono.error(ApiExceptions.conflict(
                                        "that agent is playing with other people and cannot leave yet"))
                                : members.save(RoomMemberRow.of(roomId, agentId, agent.displayName()))
                                        .doOnSuccess(m -> startRuntime(room, agent,
                                                Difficulty.parse(agent.botDifficulty())))
                                        .thenReturn(toView(agent)))));
    }

    /** Recover rooms left behind by older clients before checking whether an agent is busy. */
    Mono<Void> releaseAbandonedAgentRooms(UUID agentId, UUID ownerId) {
        if (roomService == null) return Mono.empty();
        return rooms.findLiveRoomsForAgent(agentId)
                .filter(room -> ("draughts".equals(room.gameType()) || "whot".equals(room.gameType())
                        || "ludo".equals(room.gameType()) || "goosi".equals(room.gameType())
                        || "wordbluff".equals(room.gameType()))
                        && room.hostId().equals(ownerId))
                .concatMap(room -> "lobby".equals(room.status())
                        ? roomService.abandon(room.id(), ownerId).thenReturn(true)
                        : switch (room.gameType()) {
                            case "whot" -> roomService.leaveBotWhotRoom(room.id(), ownerId);
                            case "ludo" -> roomService.leaveBotLudoRoom(room.id(), ownerId);
                            case "goosi" -> roomService.leaveBotGoosiRoom(room.id(), ownerId);
                            case "wordbluff" -> roomService.leaveBotWordBluffRoom(room.id(), ownerId);
                            default -> roomService.leaveBotDraughtsRoom(room.id(), ownerId);
                        })
                .then();
    }

    public Mono<BotAddedView> addBot(UUID roomId, UUID requesterId, String name, String difficultyRaw) {
        Difficulty difficulty = Difficulty.parse(difficultyRaw);
        return guardTournamentRoom(roomId).then(rooms.findById(roomId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("huud not found")))
                .flatMap(room -> {
                    if (!room.hostId().equals(requesterId)) {
                        return Mono.error(ApiExceptions.forbidden("only the host can add a bot"));
                    }
                    if (!"lobby".equals(room.status())) {
                        return Mono.error(ApiExceptions.conflict("the game has already started"));
                    }
                    if (adapters.create(room.gameType()) == null) {
                        return Mono.error(ApiExceptions.badRequest("bots don't support " + room.gameType() + " yet"));
                    }
                    if ("ludo".equals(room.gameType())) {
                        return members.countByRoomId(roomId).flatMap(seats -> seats >= 4
                                ? Mono.error(ApiExceptions.conflict("Ludo has four seats"))
                                : createAgentInRoom(roomId, requesterId, name, difficulty, room));
                    }
                    return createAgentInRoom(roomId, requesterId, name, difficulty, room);
                });
    }

    private Mono<BotAddedView> createAgentInRoom(UUID roomId, UUID requesterId, String name,
                                                  Difficulty difficulty, RoomRow room) {
        return agentLock.withLock(requesterId, Duration.ofSeconds(30), () ->
                            users.findAgentsOf(requesterId).count().flatMap(count -> count >= MAX_AGENTS
                                    ? Mono.error(ApiExceptions.conflict(
                                            "you can have up to 5 Cyber Agents — reuse or delete one"))
                                    : coins.debit(requesterId, BOT_COST, CoinService.REASON_BOT_ADDED, roomId)
                                            .then(usernames.resolve(null))
                                            .flatMap(username -> users.save(
                                                    UserRow.newBot(name, username, requesterId, "all",
                                                            difficulty.name().toLowerCase())))
                                            .flatMap(bot -> members.save(RoomMemberRow.of(roomId, bot.id(), name))
                                                    .doOnSuccess(m -> startRuntime(room, bot, difficulty))
                                                    .thenReturn(new BotAddedView(bot.id(), bot.displayName(),
                                                            difficulty.name().toLowerCase())))));
    }

    private Mono<RoomRow> hostedLobby(UUID roomId, UUID requesterId) {
        return guardTournamentRoom(roomId).then(rooms.findById(roomId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("huud not found")))
                .flatMap(room -> {
                    if (!room.hostId().equals(requesterId)) {
                        return Mono.error(ApiExceptions.forbidden("only the host can add a bot"));
                    }
                    if (!"lobby".equals(room.status())) {
                        return Mono.error(ApiExceptions.conflict("the game has already started"));
                    }
                    return Mono.just(room);
                });
    }

    private static BotAddedView toView(UserRow agent) {
        return new BotAddedView(agent.id(), agent.displayName(),
                agent.botDifficulty() != null ? agent.botDifficulty() : "medium");
    }

    public Mono<Void> removeBot(UUID roomId, UUID requesterId, UUID botId) {
        return guardTournamentRoom(roomId).then(rooms.findById(roomId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("huud not found")))
                .flatMap(room -> {
                    if (!room.hostId().equals(requesterId)) {
                        return Mono.error(ApiExceptions.forbidden("only the host can remove a bot"));
                    }
                    registry.stop(botId);
                    return members.findByRoomIdAndUserId(roomId, botId)
                            .flatMap(members::delete);
                });
    }

    private Mono<Void> guardTournamentRoom(UUID roomId) {
        if (championships == null) return Mono.empty();
        return championships.isTournamentRoom(roomId).flatMap(tournament -> tournament
                ? Mono.error(ApiExceptions.forbidden("Cyber Agents cannot enter championships"))
                : Mono.empty());
    }

    private void startRuntime(RoomRow room, UserRow bot, Difficulty difficulty) {
        String token = jwt.issueAccess(bot.id());
        URI uri = URI.create("ws://localhost:" + serverPort + "/ws/room/" + room.id() + "?token=" + token);
        GameBotAdapter adapter = adapters.create(room.gameType());
        String gameName = switch (room.gameType()) {
            case "draughts" -> "Draft (international draughts)";
            case "goosi" -> "Oware Abapa (a two-player sowing and capture board game)";
            case "wordbluff" -> "Word Bluff";
            case "whot" -> "Whot";
            case "ludo" -> "Ludo";
            default -> "Traitors";
        };
        BotRuntime runtime = new BotRuntime(mapper, uri, adapter, picker, bot.id().toString(), difficulty,
                bot.displayName(), gameName);
        registry.register(bot.id(), runtime);
        runtime.start();
    }
}
