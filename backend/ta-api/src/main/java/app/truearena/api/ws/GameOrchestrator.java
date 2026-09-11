package app.truearena.api.ws;

import app.truearena.api.auth.JwtService;
import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameModule;
import app.truearena.engine.GameRunner;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import app.truearena.game.truearena.ConfigValidator;
import app.truearena.game.truearena.Presets;
import app.truearena.game.truearena.TrueArenaModule;
import app.truearena.persistence.GameEventRepository;
import app.truearena.persistence.GameEventRow;
import app.truearena.persistence.GameResultRepository;
import app.truearena.persistence.GameResultRow;
import app.truearena.persistence.GameSessionRepository;
import app.truearena.persistence.GameSessionRow;
import app.truearena.persistence.RoleRepository;
import app.truearena.persistence.RoleRow;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.room.LobbyBroadcast;
import app.truearena.room.PhaseChanged;
import app.truearena.room.RoomEventLog;
import app.truearena.room.RoomLock;
import app.truearena.room.RoomRuntime;
import app.truearena.room.RoomRuntimeRegistry;
import app.truearena.ws.contract.Envelope;
import app.truearena.ws.contract.MessageType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

/**
 * The brains behind {@code /ws/room/{roomId}}: authenticates, owns the single-writer
 * lock around each room's state, drives the {@link GameRunner}, fans events out with
 * per-viewer secret-data filtering (Build Brief §8), and writes through to Postgres at
 * game end. Transport (the actual socket) is {@link RoomWebSocketHandler}.
 */
@Component
public class GameOrchestrator {

    private static final Logger log = LoggerFactory.getLogger(GameOrchestrator.class);
    private static final Duration LOCK_TTL = Duration.ofSeconds(10);

    private final RoomRuntimeRegistry registry;
    private final RoomLock lock;
    private final RoomEventLog eventLog;
    private final RoomRepository rooms;
    private final RoomMemberRepository members;
    private final GameSessionRepository sessions;
    private final RoleRepository roleRows;
    private final GameEventRepository eventRows;
    private final GameResultRepository resultRows;
    private final JwtService jwt;
    private final ObjectMapper mapper;

    public GameOrchestrator(RoomRuntimeRegistry registry, RoomLock lock, RoomEventLog eventLog,
                            RoomRepository rooms, RoomMemberRepository members,
                            GameSessionRepository sessions, RoleRepository roleRows,
                            GameEventRepository eventRows, GameResultRepository resultRows,
                            JwtService jwt, ObjectMapper mapper) {
        this.registry = registry;
        this.lock = lock;
        this.eventLog = eventLog;
        this.rooms = rooms;
        this.members = members;
        this.sessions = sessions;
        this.roleRows = roleRows;
        this.eventRows = eventRows;
        this.resultRows = resultRows;
        this.jwt = jwt;
        this.mapper = mapper;
    }

    public record Authed(UUID roomId, String userId) {
    }

    // ---------------------------------------------------------------- connect

    public Mono<Authed> authenticate(String roomIdRaw, String token) {
        return Mono.fromCallable(() -> {
                    UUID roomId = UUID.fromString(roomIdRaw);
                    UUID userId = jwt.parseAccess(token);
                    return new Authed(roomId, userId.toString());
                })
                .onErrorMap(e -> new SecurityException("bad token"))
                .flatMap(a -> members.findByRoomIdAndUserId(a.roomId(), UUID.fromString(a.userId()))
                        .map(m -> a)
                        .switchIfEmpty(Mono.error(new SecurityException("not a member of this room"))));
    }

    public Mono<RoomRuntime> ensureRuntime(UUID roomId) {
        return registry.find(roomId)
                .map(Mono::just)
                .orElseGet(() -> rooms.findById(roomId)
                        .switchIfEmpty(Mono.error(new IllegalStateException("room not found")))
                        .map(room -> registry.computeIfAbsent(roomId, id -> new RoomRuntime(id, room.hostId().toString()))));
    }

    public Mono<Void> onConnect(RoomRuntime rt, String userId) {
        rt.connectedUserIds.add(userId);
        return setConnection(rt.roomId, userId, "connected")
                .then(broadcastLobby(rt, "MEMBER_CONNECTED", Map.of("userId", userId)));
    }

    public Mono<Void> onDisconnect(RoomRuntime rt, String userId) {
        rt.connectedUserIds.remove(userId);
        rt.unicast.remove(userId);
        Mono<Void> disconnect = setConnection(rt.roomId, userId, "disconnected");
        Mono<Void> migrate = userId.equals(rt.hostUserId) ? migrateHost(rt) : Mono.empty();
        return disconnect.then(migrate).then(broadcastLobby(rt, "MEMBER_DISCONNECTED", Map.of("userId", userId)));
    }

    private Mono<Void> migrateHost(RoomRuntime rt) {
        if (rt.connectedUserIds.isEmpty()) {
            return Mono.empty();
        }
        String newHost = rt.connectedUserIds.iterator().next();
        rt.hostUserId = newHost;
        return rooms.findById(rt.roomId)
                .flatMap(r -> rooms.save(new RoomRow(r.id(), r.code(), r.groupId(), UUID.fromString(newHost), r.status(), r.createdAt())))
                .then(broadcastLobby(rt, "HOST_CHANGED", Map.of("hostId", newHost)));
    }

    private Mono<Void> setConnection(UUID roomId, String userId, String status) {
        return members.findByRoomIdAndUserId(roomId, UUID.fromString(userId))
                .flatMap(m -> members.save(new RoomMemberRow(m.id(), m.roomId(), m.userId(), m.nickname(), status, m.readyState(), m.joinedAt())))
                .then();
    }

    private Mono<Void> broadcastLobby(RoomRuntime rt, String type, Map<String, Object> data) {
        rt.bus.tryEmitNext(new LobbyBroadcast(type, data));
        return Mono.empty();
    }

    // ---------------------------------------------------------------- inbound frames

    public Mono<Void> handleFrame(RoomRuntime rt, String userId, String text) {
        Envelope in;
        try {
            in = mapper.readValue(text, Envelope.class);
        } catch (Exception e) {
            return tellError(rt, userId, "BAD_ENVELOPE", "could not parse frame");
        }
        try {
            return switch (in.type()) {
                case HELLO -> handleHello(rt, userId, in);
                case READY_SET -> handleReady(rt, userId, in);
                case GAME_START -> handleGameStart(rt, userId);
                case PLAYER_ACTION -> handlePlayerAction(rt, userId, in);
                case PING -> {
                    rt.tellUser(userId, Envelope.of(MessageType.PONG, Map.of()));
                    yield Mono.empty();
                }
                default -> tellError(rt, userId, "UNSUPPORTED", "no handler for " + in.type());
            };
        } catch (Exception e) {
            log.warn("frame handling failed for room {} user {}: {}", rt.roomId, userId, e.toString());
            return tellError(rt, userId, "INTERNAL", "could not process that frame");
        }
    }

    @SuppressWarnings("unchecked")
    private Mono<Void> handleHello(RoomRuntime rt, String userId, Envelope in) {
        long lastSeq = numberOf(in.payload().get("lastSeq"));
        if (!rt.started()) {
            return sendLobbySnapshot(rt, userId);
        }
        if (lastSeq > 0) {
            return eventLog.replayAfter(rt.roomId, lastSeq)
                    .flatMap(json -> Mono.fromCallable(() -> mapper.readValue(json, GameEvent.class)))
                    .filter(ge -> visibleTo(rt, ge, userId))
                    .doOnNext(ge -> rt.tellUser(userId, eventEnvelope(ge)))
                    .then()
                    .doOnSuccess(v -> sendPhase(rt, userId));
        }
        sendSnapshot(rt, userId);
        sendPhase(rt, userId);
        return Mono.empty();
    }

    private Mono<Void> sendLobbySnapshot(RoomRuntime rt, String userId) {
        return rooms.findById(rt.roomId)
                .zipWith(members.findByRoomId(rt.roomId).collectList())
                .doOnNext(t -> {
                    RoomRow room = t.getT1();
                    List<Map<String, Object>> mem = t.getT2().stream().map(m -> Map.<String, Object>of(
                            "userId", m.userId().toString(),
                            "nickname", m.nickname() == null ? "" : m.nickname(),
                            "ready", m.readyState(),
                            "connectionStatus", m.connectionStatus()
                    )).toList();
                    Map<String, Object> payload = new LinkedHashMap<>();
                    payload.put("lobby", true);
                    payload.put("roomId", room.id().toString());
                    payload.put("code", room.code());
                    payload.put("hostId", room.hostId().toString());
                    payload.put("status", room.status());
                    payload.put("members", mem);
                    rt.tellUser(userId, Envelope.of(MessageType.SNAPSHOT, payload));
                })
                .then();
    }

    private void sendSnapshot(RoomRuntime rt, String userId) {
        Map<String, Object> view = new LinkedHashMap<>(rt.module().visibleStateFor(rt.state(), userId).data());
        view.put("lobby", false);
        rt.tellUser(userId, Envelope.of(MessageType.SNAPSHOT, view));
    }

    private void sendPhase(RoomRuntime rt, String userId) {
        if (!rt.started()) {
            return;
        }
        rt.tellUser(userId, Envelope.of(MessageType.PHASE, Map.of("phase", rt.state().phase(), "round", rt.state().round())));
    }

    private Mono<Void> handleReady(RoomRuntime rt, String userId, Envelope in) {
        boolean ready = Boolean.TRUE.equals(in.payload().get("ready"));
        return members.findByRoomIdAndUserId(rt.roomId, UUID.fromString(userId))
                .flatMap(m -> members.save(new RoomMemberRow(m.id(), m.roomId(), m.userId(), m.nickname(), m.connectionStatus(), ready, m.joinedAt())))
                .then(broadcastLobby(rt, "READY_CHANGED", Map.of("userId", userId, "ready", ready)));
    }

    // ---------------------------------------------------------------- game start / actions

    private Mono<Void> handleGameStart(RoomRuntime rt, String userId) {
        if (!userId.equals(rt.hostUserId)) {
            return tellError(rt, userId, "NOT_HOST", "only the host can start the game");
        }
        if (rt.started()) {
            return tellError(rt, userId, "ALREADY_STARTED", "this room's game is already running");
        }
        return lock.withLock(rt.roomId, LOCK_TTL, () -> members.findByRoomId(rt.roomId).collectList().flatMap(memberRows -> {
            List<String> playerIds = memberRows.stream().map(m -> m.userId().toString()).toList();
            GameConfig cfg = withPlayers(Presets.CLASSIC_CONSPIRACY.config(), playerIds.size());
            ConfigValidator.Result validation = ConfigValidator.validate(cfg);
            if (!validation.ok()) {
                return tellError(rt, userId, "BAD_CONFIG", String.join("; ", validation.errors()));
            }

            TrueArenaModule module = new TrueArenaModule();
            long seed = ThreadLocalRandom.current().nextLong();
            var state = module.initialState(playerIds, cfg, RandomSource.seeded(seed));

            return sessions.save(GameSessionRow.start(rt.roomId, module.gameType(), writeJson(cfg), cfg.catalogVersion(), seed))
                    .flatMap(session -> {
                        rt.config = cfg;
                        rt.start(module, state, session.id());
                        recomputeRoles(rt);
                        Mono<Void> persistRoles = Flux.fromIterable(rt.roleByUser().entrySet())
                                .concatMap(e -> roleRows.save(RoleRow.of(session.id(), UUID.fromString(e.getKey()), e.getValue())))
                                .then();
                        return persistRoles
                                .then(updateRoomStatus(rt.roomId, "in_game"))
                                .then(afterMutation(rt, state.events()));
                    });
        }));
    }

    private Mono<Void> handlePlayerAction(RoomRuntime rt, String userId, Envelope in) {
        if (!rt.started()) {
            return tellError(rt, userId, "NOT_STARTED", "this room hasn't started a game yet");
        }
        String action = String.valueOf(in.payload().get("action"));
        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) in.payload().getOrDefault("data", Map.of());
        Object rawActionId = in.payload().get("actionId");
        String actionId = rawActionId != null ? rawActionId.toString() : UUID.randomUUID().toString();

        boolean hostOnly = "REVEAL_NEXT".equals(action) || "ADVANCE_PHASE".equals(action);
        if (hostOnly && !userId.equals(rt.hostUserId)) {
            return tellError(rt, userId, "NOT_HOST", "only the host can do that");
        }

        return lock.withLock(rt.roomId, LOCK_TTL, () -> {
            GameRunner runner = new GameRunner(rt.module());
            GameRunner.Step step;
            try {
                step = runner.apply(rt.state(), new PlayerAction(actionId, userId, action, data));
            } catch (RuleViolation rv) {
                return tellError(rt, userId, rv.code(), rv.getMessage());
            }
            rt.setState(step.state());
            return afterMutation(rt, step.events());
        });
    }

    private void triggerElapse(RoomRuntime rt, String expectedPhase) {
        lock.withLock(rt.roomId, LOCK_TTL, () -> {
            if (rt.state() == null || rt.state().finished() || !expectedPhase.equals(rt.state().phase())) {
                return Mono.empty();
            }
            GameRunner runner = new GameRunner(rt.module());
            GameRunner.Step step = runner.elapse(rt.state(), expectedPhase);
            rt.setState(step.state());
            return afterMutation(rt, step.events());
        }).subscribe(v -> { }, e -> log.warn("timer elapse failed for room {}: {}", rt.roomId, e.toString()));
    }

    // ---------------------------------------------------------------- shared post-mutation pipeline

    private Mono<Void> afterMutation(RoomRuntime rt, List<GameEvent> newEvents) {
        recomputeRoles(rt);
        Mono<Void> appendAndBroadcast = Flux.fromIterable(newEvents)
                .concatMap(ge -> eventLog.append(rt.roomId, writeJson(ge)).doOnSuccess(v -> rt.bus.tryEmitNext(ge)))
                .then();
        rescheduleTimer(rt);
        broadcastPhase(rt);
        Mono<Void> finish = rt.state().finished() ? finishGame(rt) : Mono.empty();
        return appendAndBroadcast.then(finish);
    }

    @SuppressWarnings("unchecked")
    private void recomputeRoles(RoomRuntime rt) {
        var broadcast = rt.module().broadcastState(rt.state()).data();
        Object playersObj = broadcast.get("players");
        Map<String, String> byUser = new LinkedHashMap<>();
        if (playersObj instanceof List<?> players) {
            for (Object p : players) {
                String uid = String.valueOf(p);
                Object role = rt.module().visibleStateFor(rt.state(), uid).data().get("yourRole");
                if (role != null) {
                    byUser.put(uid, role.toString());
                }
            }
        }
        rt.setRoleByUser(byUser);
    }

    private void rescheduleTimer(RoomRuntime rt) {
        String phase = rt.state().phase();
        if (phase.equals(rt.timerForPhase)) {
            return;
        }
        rt.cancelTimer();
        rt.timerForPhase = phase;
        if (rt.config == null) {
            return;
        }
        int secs = rt.module().definePhases(rt.config).stream()
                .filter(p -> p.name().equals(phase))
                .findFirst()
                .map(p -> p.timerSeconds())
                .orElse(0);
        if (secs > 0) {
            rt.timer = Mono.delay(Duration.ofSeconds(secs)).subscribe(x -> triggerElapse(rt, phase));
        }
    }

    private void broadcastPhase(RoomRuntime rt) {
        rt.bus.tryEmitNext(new PhaseChanged(rt.state().phase(), rt.state().round()));
    }

    private Mono<Void> finishGame(RoomRuntime rt) {
        var win = rt.module().checkWinCondition(rt.state()).orElse(null);
        Mono<Void> saveResult = win == null ? Mono.empty()
                : resultRows.save(GameResultRow.of(rt.gameSessionId, win.winningSide(), writeJson(win.perPlayerOutcome()))).then();
        Mono<Void> flushEvents = eventLog.replayAfter(rt.roomId, 0)
                .index()
                .concatMap(t -> Mono.fromCallable(() -> mapper.readValue(t.getT2(), GameEvent.class))
                        .flatMap(ge -> eventRows.save(GameEventRow.of(rt.gameSessionId, ge.seq(), ge.type(),
                                writeJson(ge.payload()), ge.visibility().scope(), ge.visibility().key()))))
                .then();
        Mono<Void> endSession = sessions.findById(rt.gameSessionId)
                .flatMap(s -> sessions.save(new GameSessionRow(s.id(), s.roomId(), s.gameType(), s.config(), s.configPresetId(),
                        s.catalogVersion(), s.rngSeed(), rt.state().phase(), rt.state().round(), null, s.startedAt(), Instant.now())))
                .then();
        Mono<Void> endRoom = updateRoomStatus(rt.roomId, "ended");
        return saveResult.then(flushEvents).then(endSession).then(endRoom);
    }

    private Mono<Void> updateRoomStatus(UUID roomId, String status) {
        return rooms.findById(roomId)
                .flatMap(r -> rooms.save(new RoomRow(r.id(), r.code(), r.groupId(), r.hostId(), status, r.createdAt())))
                .then();
    }

    // ---------------------------------------------------------------- visibility + wire helpers

    private boolean visibleTo(RoomRuntime rt, GameEvent ge, String userId) {
        var v = ge.visibility();
        if (v.isPublic()) {
            return true;
        }
        if ("player".equals(v.scope())) {
            return userId.equals(v.key());
        }
        if ("role".equals(v.scope())) {
            String actual = rt.roleByUser().get(userId);
            return actual != null && roleGroupMatches(actual, v.key());
        }
        return false;
    }

    /** A recruited Traitor still counts as "traitor" for event routing. */
    private boolean roleGroupMatches(String actualRole, String wantedRole) {
        return actualRole.equals(wantedRole) || ("traitor".equals(wantedRole) && "recruited_traitor".equals(actualRole));
    }

    Mono<Envelope> toEnvelope(RoomRuntime rt, Object msg, String userId) {
        if (msg instanceof GameEvent ge) {
            return visibleTo(rt, ge, userId) ? Mono.just(eventEnvelope(ge)) : Mono.empty();
        }
        if (msg instanceof LobbyBroadcast lb) {
            return Mono.just(Envelope.of(MessageType.EVENT, Map.of("type", lb.type(), "data", lb.data())));
        }
        if (msg instanceof PhaseChanged pc) {
            return Mono.just(Envelope.of(MessageType.PHASE, Map.of("phase", pc.phase(), "round", pc.round())));
        }
        if (msg instanceof Envelope env) {
            return Mono.just(env);
        }
        return Mono.empty();
    }

    private Envelope eventEnvelope(GameEvent ge) {
        return Envelope.of(MessageType.EVENT, Map.of("seq", ge.seq(), "type", ge.type(), "data", ge.payload()));
    }

    private Mono<Void> tellError(RoomRuntime rt, String userId, String code, String message) {
        rt.tellUser(userId, Envelope.of(MessageType.ERROR, Map.of("code", code, "message", message == null ? "" : message)));
        return Mono.empty();
    }

    private GameConfig withPlayers(GameConfig base, int n) {
        GameConfig.Table t = base.table();
        return new GameConfig(base.catalogVersion(), base.preset(),
                new GameConfig.Table(n, t.minPlayers(), t.maxPlayers(), t.adminOverride(), t.traitorCurve()),
                base.timers(), base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(),
                base.suddenDeathSeconds(), base.afk(), base.voteReveal(), base.endgameVeil(), base.twists());
    }

    private static long numberOf(Object o) {
        return o instanceof Number n ? n.longValue() : 0L;
    }

    String writeJson(Object value) {
        try {
            return mapper.writeValueAsString(value);
        } catch (Exception e) {
            throw new IllegalStateException("cannot serialize " + value.getClass(), e);
        }
    }
}
