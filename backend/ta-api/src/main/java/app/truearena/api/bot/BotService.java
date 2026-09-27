package app.truearena.api.bot;

import app.truearena.api.auth.JwtService;
import app.truearena.api.auth.UsernameGenerator;
import app.truearena.api.bot.BotDtos.BotAddedView;
import app.truearena.api.coins.CoinService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.net.URI;
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

    /** A soft throttle so a room can't be filled with free bots without limit — see docs/DEV_REFERENCE.md. */
    private static final long BOT_COST = 20;

    @Value("${server.port:8080}")
    private int serverPort;

    public BotService(RoomRepository rooms, RoomMemberRepository members, UserRepository users,
                       UsernameGenerator usernames, JwtService jwt, ObjectMapper mapper,
                       GameBotAdapterFactory adapters, LlmMovePicker picker, BotRuntimeRegistry registry, CoinService coins) {
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
    }

    /** The caller's saved agents for one game, so the lobby can offer them instead of asking for a name again. */
    public Flux<BotAddedView> listAgents(UUID ownerId, String gameType) {
        return users.findAgentsOf(ownerId, gameType).map(BotService::toView);
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
                    return members.countLiveRoomsFor(agentId)
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
                            if (!room.gameType().equals(agent.botGameType())) {
                                return Mono.error(ApiExceptions.badRequest(
                                        "that agent plays " + agent.botGameType() + ", not " + room.gameType()));
                            }
                            return members.findByRoomIdAndUserId(roomId, agentId)
                                    .flatMap(existing -> Mono.<BotAddedView>error(
                                            ApiExceptions.conflict("that agent is already in this room")))
                                    .switchIfEmpty(Mono.defer(() ->
                                            members.save(RoomMemberRow.of(roomId, agentId, agent.displayName()))
                                                    .doOnSuccess(m -> startRuntime(room, agent,
                                                            Difficulty.parse(agent.botDifficulty())))
                                                    .thenReturn(toView(agent))));
                        }));
    }

    public Mono<BotAddedView> addBot(UUID roomId, UUID requesterId, String name, String difficultyRaw) {
        Difficulty difficulty = Difficulty.parse(difficultyRaw);
        return rooms.findById(roomId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("room not found")))
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
                    return coins.debit(requesterId, BOT_COST, CoinService.REASON_BOT_ADDED, roomId)
                            .then(usernames.resolve(null))
                            .flatMap(username -> users.save(
                                    UserRow.newBot(name, username, requesterId, room.gameType(),
                                            difficulty.name().toLowerCase())))
                            .flatMap(bot -> members.save(RoomMemberRow.of(roomId, bot.id(), name))
                                    .doOnSuccess(m -> startRuntime(room, bot, difficulty))
                                    .thenReturn(new BotAddedView(bot.id(), bot.displayName(), difficulty.name().toLowerCase())));
                });
    }

    private Mono<RoomRow> hostedLobby(UUID roomId, UUID requesterId) {
        return rooms.findById(roomId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("room not found")))
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
        return rooms.findById(roomId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("room not found")))
                .flatMap(room -> {
                    if (!room.hostId().equals(requesterId)) {
                        return Mono.error(ApiExceptions.forbidden("only the host can remove a bot"));
                    }
                    registry.stop(botId);
                    return members.findByRoomIdAndUserId(roomId, botId)
                            .flatMap(members::delete);
                });
    }

    private void startRuntime(RoomRow room, UserRow bot, Difficulty difficulty) {
        String token = jwt.issueAccess(bot.id());
        URI uri = URI.create("ws://localhost:" + serverPort + "/ws/room/" + room.id() + "?token=" + token);
        GameBotAdapter adapter = adapters.create(room.gameType());
        String gameName = switch (room.gameType()) {
            case "draughts" -> "Draft (international draughts)";
            case "goosi" -> "Goosi (a sowing and capture board game)";
            case "wordbluff" -> "Word Bluff";
            case "whot" -> "Whot";
            default -> "Traitors";
        };
        BotRuntime runtime = new BotRuntime(mapper, uri, adapter, picker, bot.id().toString(), difficulty,
                bot.displayName(), gameName);
        registry.register(bot.id(), runtime);
        runtime.start();
    }
}
