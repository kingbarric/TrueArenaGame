package app.truearena.api.bot;

import app.truearena.api.auth.JwtService;
import app.truearena.api.bot.BotDtos.BotAddedView;
import app.truearena.api.championship.ChampionshipService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.room.RoomLock;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.net.URI;
import java.time.Duration;
import java.util.UUID;

/**
 * Seats reusable system Cyber Agents in a lobby. An agent's chosen name,
 * difficulty and live runtime belong to that room, so a pool identity can be
 * used in simultaneous Huuds without any ownership or "already busy" state.
 */
@Service
public class BotService {

    private final RoomRepository rooms;
    private final RoomMemberRepository members;
    private final UserRepository users;
    private final JwtService jwt;
    private final ObjectMapper mapper;
    private final GameBotAdapterFactory adapters;
    private final LlmMovePicker picker;
    private final BotRuntimeRegistry registry;
    private final RoomLock agentLock;
    @Autowired(required = false)
    private ChampionshipService championships;

    @Value("${server.port:8080}")
    private int serverPort;

    public BotService(RoomRepository rooms, RoomMemberRepository members, UserRepository users,
                      JwtService jwt, ObjectMapper mapper, GameBotAdapterFactory adapters,
                      LlmMovePicker picker, BotRuntimeRegistry registry, RoomLock agentLock) {
        this.rooms = rooms;
        this.members = members;
        this.users = users;
        this.jwt = jwt;
        this.mapper = mapper;
        this.adapters = adapters;
        this.picker = picker;
        this.registry = registry;
        this.agentLock = agentLock;
    }

    /** Legacy mobile clients see no saved inventory and fall through to Add Agent. */
    public Flux<BotAddedView> listAgents(UUID ownerId, String gameType) {
        return Flux.empty();
    }

    public Mono<Void> deleteAgent(UUID agentId, UUID requesterId) {
        return Mono.error(ApiExceptions.notFound("saved Cyber Agents are no longer used"));
    }

    public Mono<BotAddedView> rename(UUID agentId, UUID requesterId, String newName) {
        return Mono.error(ApiExceptions.notFound("Cyber Agent names are chosen for each huud"));
    }

    /**
     * Compatibility for an older app that picked a saved agent immediately
     * before this backend was deployed. Its preferences are copied into a new
     * room-scoped pool seat; the old identity itself is never attached.
     */
    public Mono<BotAddedView> addExistingAgent(UUID roomId, UUID requesterId, UUID agentId) {
        return users.findById(agentId)
                .filter(agent -> agent.isBot() && requesterId.equals(agent.ownerUserId()))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("not your legacy agent")))
                .flatMap(agent -> addBot(roomId, requesterId, agent.displayName(), agent.botDifficulty()));
    }

    public Mono<BotAddedView> addBot(UUID roomId, UUID requesterId, String name, String difficultyRaw) {
        Difficulty difficulty = Difficulty.parse(difficultyRaw);
        return hostedLobby(roomId, requesterId)
                .flatMap(room -> agentLock.withLock(roomId, Duration.ofSeconds(30),
                        () -> addPoolAgent(room, name.trim(), difficulty)));
    }

    private Mono<BotAddedView> addPoolAgent(RoomRow room, String name, Difficulty difficulty) {
        if (adapters.create(room.gameType()) == null) {
            return Mono.error(ApiExceptions.badRequest("Cyber Agents don't support " + room.gameType() + " yet"));
        }
        return members.countByRoomId(room.id()).flatMap(seats -> {
            if ("ludo".equals(room.gameType()) && seats >= 4) {
                return Mono.error(ApiExceptions.conflict("Ludo has four seats"));
            }
            return users.findSystemAgentForRoom(room.id())
                    .switchIfEmpty(Mono.error(ApiExceptions.conflict("no Cyber Agent seat is available")))
                    .flatMap(agent -> members.save(RoomMemberRow.bot(room.id(), agent.id(), name,
                                    difficulty.name().toLowerCase()))
                            .doOnSuccess(ignored -> startRuntime(room, agent.id(), name, difficulty))
                            .thenReturn(new BotAddedView(agent.id(), name,
                                    difficulty.name().toLowerCase())));
        });
    }

    public Mono<Void> removeBot(UUID roomId, UUID requesterId, UUID botId) {
        return hostedLobby(roomId, requesterId)
                .then(members.findByRoomIdAndUserId(roomId, botId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("Cyber Agent is not in this huud")))
                .flatMap(member -> users.findById(member.userId())
                        .filter(UserRow::isBot)
                        .switchIfEmpty(Mono.error(ApiExceptions.forbidden("that player is not a Cyber Agent")))
                        .then(Mono.fromRunnable(() -> registry.stop(roomId, botId)))
                        .then(members.delete(member)));
    }

    private Mono<RoomRow> hostedLobby(UUID roomId, UUID requesterId) {
        return guardTournamentRoom(roomId).then(rooms.findById(roomId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("huud not found")))
                .flatMap(room -> {
                    if (!room.hostId().equals(requesterId)) {
                        return Mono.error(ApiExceptions.forbidden("only the host can add a Cyber Agent"));
                    }
                    if (!"lobby".equals(room.status())) {
                        return Mono.error(ApiExceptions.conflict("the game has already started"));
                    }
                    return Mono.just(room);
                });
    }

    private Mono<Void> guardTournamentRoom(UUID roomId) {
        if (championships == null) return Mono.empty();
        return championships.isTournamentRoom(roomId).flatMap(tournament -> tournament
                ? Mono.error(ApiExceptions.forbidden("Cyber Agents cannot enter championships"))
                : Mono.empty());
    }

    void startRuntime(RoomRow room, UUID botId, String name, Difficulty difficulty) {
        String token = jwt.issueAccess(botId);
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
        BotRuntime runtime = new BotRuntime(mapper, uri, adapter, picker, botId.toString(), difficulty,
                name, gameName);
        registry.register(room.id(), botId, runtime);
        runtime.start();
    }
}
