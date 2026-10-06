package app.truearena.api.ws;

import app.truearena.api.auth.JwtService;
import app.truearena.api.championship.ChampionshipService;
import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameModule;
import app.truearena.engine.GameRunner;
import app.truearena.engine.GameState;
import app.truearena.api.bot.BotRuntimeRegistry;
import app.truearena.api.coins.CoinService;
import app.truearena.engine.Phase;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import app.truearena.game.draughts.DraughtsConfig;
import app.truearena.game.draughts.DraughtsModule;
import app.truearena.game.goosi.GoosiConfig;
import app.truearena.game.goosi.GoosiModule;
import app.truearena.game.whot.WhotConfig;
import app.truearena.game.whot.WhotModule;
import app.truearena.game.ludo.LudoConfig;
import app.truearena.game.ludo.LudoModule;
import app.truearena.game.truearena.ConfigValidator;
import app.truearena.game.truearena.Presets;
import app.truearena.game.truearena.TrueArenaModule;
import app.truearena.game.wordbluff.WordBluffConfig;
import app.truearena.game.wordbluff.WordBluffModule;
import app.truearena.persistence.GameEventRepository;
import app.truearena.persistence.GameEventRow;
import app.truearena.persistence.GameResultRepository;
import app.truearena.persistence.GameResultRow;
import app.truearena.persistence.GameSessionRepository;
import app.truearena.persistence.GameSessionRow;
import app.truearena.persistence.PlayerStatsRepository;
import app.truearena.persistence.PlayerStatsRow;
import app.truearena.persistence.RoleRepository;
import app.truearena.persistence.RoleRow;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.room.ChatMessage;
import app.truearena.room.LobbyBroadcast;
import app.truearena.room.PhaseChanged;
import app.truearena.room.RoomEventLog;
import app.truearena.room.RoomLock;
import app.truearena.room.RoomRuntime;
import app.truearena.room.RoomRuntimeRegistry;
import app.truearena.ws.contract.Envelope;
import app.truearena.ws.contract.MessageType;
import app.truearena.voice.LiveKitRoomAdmin;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.beans.factory.annotation.Autowired;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
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
    private final PlayerStatsRepository statsRows;
    private final UserRepository users;
    private final JwtService jwt;
    private final ObjectMapper mapper;
    private final app.truearena.api.coins.CoinService coins;
    @Autowired(required = false)
    private ChampionshipService championships;
    @Autowired(required = false)
    private BotRuntimeRegistry botRuntimes;
    @Autowired(required = false)
    private app.truearena.api.push.PushNotificationService push;
    @Autowired(required = false)
    private LiveKitRoomAdmin voiceAdmin;
    @Autowired(required = false)
    private app.truearena.api.competitive.RatingService ratings;

    public GameOrchestrator(RoomRuntimeRegistry registry, RoomLock lock, RoomEventLog eventLog,
                            RoomRepository rooms, RoomMemberRepository members,
                            GameSessionRepository sessions, RoleRepository roleRows,
                            GameEventRepository eventRows, GameResultRepository resultRows,
                            PlayerStatsRepository statsRows, UserRepository users, JwtService jwt, ObjectMapper mapper,
                            app.truearena.api.coins.CoinService coins) {
        this.registry = registry;
        this.lock = lock;
        this.eventLog = eventLog;
        this.rooms = rooms;
        this.members = members;
        this.sessions = sessions;
        this.roleRows = roleRows;
        this.eventRows = eventRows;
        this.users = users;
        this.resultRows = resultRows;
        this.statsRows = statsRows;
        this.jwt = jwt;
        this.mapper = mapper;
        this.coins = coins;
    }

    public record Authed(UUID roomId, String userId, boolean spectator) {
    }

    // ---------------------------------------------------------------- connect

    /**
     * {@code spectate=true} skips the room-membership check entirely — any
     * authenticated user (guests included) can watch any room by code, same
     * discovery path as joining. A spectator never gets a {@code room_members}
     * row; see {@link RoomRuntime#spectatorUserIds}.
     */
    public Mono<Authed> authenticate(String roomIdRaw, String token, boolean spectate) {
        Mono<Authed> parsed = Mono.fromCallable(() -> {
                    UUID roomId = UUID.fromString(roomIdRaw);
                    UUID userId = jwt.parseAccess(token);
                    return new Authed(roomId, userId.toString(), spectate);
                })
                .onErrorMap(e -> new SecurityException("bad token"));
        if (spectate) {
            return parsed.flatMap(a -> championships == null ? Mono.just(a)
                    : championships.spectatorAllowed(a.roomId(), UUID.fromString(a.userId()))
                    .flatMap(allowed -> allowed ? Mono.just(a)
                            : Mono.error(new SecurityException("private championship match"))));
        }
        return parsed.flatMap(a -> members.findByRoomIdAndUserId(a.roomId(), UUID.fromString(a.userId()))
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
                .then(championships == null ? Mono.empty()
                        : championships.connection(rt.roomId, UUID.fromString(userId), true))
                .then(broadcastLobby(rt, "MEMBER_CONNECTED", Map.of("userId", userId)));
    }

    public Mono<Void> onDisconnect(RoomRuntime rt, String userId) {
        rt.connectedUserIds.remove(userId);
        rt.unicast.remove(userId);
        // Nothing about the game state changes on a disconnect, so
        // pushTurnReminders' own dedupe (keyed on the set of players-to-act
        // changing) would never fire here on its own — but if it's already
        // this player's turn, they just went from "watching the board" to
        // "not watching it" and should get the reminder now, not next move.
        if (push != null && rt.started() && rt.module().playersToAct(rt.state()).contains(userId)) {
            pushToWhoeverIsOffline(rt, Set.of(userId));
        }
        Mono<Void> disconnect = setConnection(rt.roomId, userId, "disconnected");
        // Mobile networks often drop a socket for a few seconds. Give its host
        // time to reconnect before transferring control to another player.
        Mono<Void> migrate = userId.equals(rt.hostUserId)
                ? Mono.delay(Duration.ofSeconds(10))
                    .filter(ignored -> !rt.connectedUserIds.contains(userId)
                            && userId.equals(rt.hostUserId))
                    .flatMap(ignored -> migrateHost(rt)).then()
                : Mono.empty();
        if (championships != null) {
            Mono<Void> freeze = rt.tournament ? lock.withLock(rt.roomId, LOCK_TTL, () -> {
                if (rt.started() && !rt.paused && !rt.state().finished()) {
                    rt.paused = true;
                    freezeTimer(rt);
                }
                return Mono.empty();
            }) : Mono.empty();
            return freeze.then(rt.tournament ? persistTournamentClock(rt.roomId) : Mono.empty())
                    .then(disconnect).then(championships.isTournamentRoom(rt.roomId).flatMap(tournament ->
                    tournament ? championships.connection(rt.roomId, UUID.fromString(userId), false)
                            : migrate)).then(broadcastLobby(rt, "MEMBER_DISCONNECTED", Map.of("userId", userId)));
        }
        return disconnect.then(migrate).then(broadcastLobby(rt, "MEMBER_DISCONNECTED", Map.of("userId", userId)));
    }

    /** Spectators never touch {@code room_members} or host migration — they're not participants. */
    public Mono<Void> onSpectatorConnect(RoomRuntime rt, String userId) {
        rt.spectatorUserIds.add(userId);
        if (rt.started()) sendSnapshot(rt, userId);
        return broadcastLobby(rt, "SPECTATOR_COUNT", Map.of("count", rt.spectatorUserIds.size()));
    }

    public Mono<Void> onSpectatorDisconnect(RoomRuntime rt, String userId) {
        rt.spectatorUserIds.remove(userId);
        boolean wasSpeaker = rt.spectatorVoiceSpeakers.remove(userId);
        rt.spectatorVoiceRequests.remove(userId);
        rt.mutedSpectatorVoiceSpeakers.remove(userId);
        rt.unicast.remove(userId);
        if (wasSpeaker) {
            rt.bus.tryEmitNext(new LobbyBroadcast("SPECTATOR_VOICE_REMOVED", Map.of("userId", userId)));
        }
        return (wasSpeaker ? removeFromVoice(rt, userId) : Mono.<Void>empty())
                .then(broadcastLobby(rt, "SPECTATOR_COUNT", Map.of("count", rt.spectatorUserIds.size())));
    }

    /**
     * Hands the room to somebody else when the host drops out — but only
     * ever to a person. A Cyber Agent connects over the socket like any
     * other player, so the obvious "first connected user" picked one
     * whenever a human left a bot behind: a room nobody can start, add to
     * or end, and a bot row that rooms then depend on and which can no
     * longer be deleted. If everyone left is a bot the host stays put; the
     * room is over anyway.
     */
    private Mono<Void> migrateHost(RoomRuntime rt) {
        if (rt.connectedUserIds.isEmpty()) {
            return Mono.empty();
        }
        return Flux.fromIterable(List.copyOf(rt.connectedUserIds))
                .concatMap(id -> users.findById(UUID.fromString(id)))
                .filter(u -> !u.isBot())
                .next()
                .flatMap(human -> {
                    String newHost = human.id().toString();
                    rt.hostUserId = newHost;
                    return rooms.findById(rt.roomId)
                            .flatMap(r -> rooms.save(r.withHost(human.id())))
                            .then(broadcastLobby(rt, "HOST_CHANGED", Map.of("hostId", newHost)));
                });
    }

    private Mono<Void> setConnection(UUID roomId, String userId, String status) {
        return members.findByRoomIdAndUserId(roomId, UUID.fromString(userId))
                .flatMap(m -> members.save(new RoomMemberRow(m.id(), m.roomId(), m.userId(), m.nickname(),
                        status, m.readyState(), m.botDifficulty(), m.joinedAt())))
                .then();
    }

    private Mono<Void> broadcastLobby(RoomRuntime rt, String type, Map<String, Object> data) {
        rt.bus.tryEmitNext(new LobbyBroadcast(type, data));
        return Mono.empty();
    }

    // ---------------------------------------------------------------- inbound frames

    public Mono<Void> handleFrame(RoomRuntime rt, String userId, String text) {
        return handleFrame(rt, userId, text, rt.spectatorUserIds.contains(userId));
    }

    public Mono<Void> handleFrame(RoomRuntime rt, String userId, String text, boolean spectator) {
        Envelope in;
        try {
            in = mapper.readValue(text, Envelope.class);
        } catch (Exception e) {
            return tellError(rt, userId, "BAD_ENVELOPE", "could not parse frame");
        }
        if (spectator
                && in.type() != MessageType.HELLO && in.type() != MessageType.PING
                && in.type() != MessageType.CHAT_SEND
                && in.type() != MessageType.SPECTATOR_VOICE_REQUEST) {
            return tellError(rt, userId, "SPECTATOR_READ_ONLY", "spectators can watch and comment, but cannot control the game");
        }
        if (spectator && rt.tournament && in.type() == MessageType.CHAT_SEND)
            return tellError(rt, userId, "SPECTATOR_READ_ONLY", "championship matches are read-only for viewers");
        try {
            return switch (in.type()) {
                case HELLO -> handleHello(rt, userId, in);
                case READY_SET -> handleReady(rt, userId, in);
                case GAME_START -> handleGameStart(rt, userId, in.payload());
                case PLAYER_ACTION -> handlePlayerAction(rt, userId, in);
                case CHAT_SEND -> handleChat(rt, userId, in, spectator);
                case PAUSE_TOGGLE -> handlePauseToggle(rt, userId);
                case MUTE_SPECTATORS_TOGGLE -> handleMuteSpectatorsToggle(rt, userId);
                case SPECTATOR_VOICE_REQUEST -> handleSpectatorVoiceRequest(rt, userId, spectator);
                case SPECTATOR_VOICE_APPROVE -> handleSpectatorVoiceApprove(rt, userId, in);
                case SPECTATOR_VOICE_DECLINE -> handleSpectatorVoiceDecline(rt, userId, in);
                case SPECTATOR_VOICE_MUTE_TOGGLE -> handleSpectatorVoiceMuteToggle(rt, userId, in);
                case SPECTATOR_VOICE_REMOVE -> handleSpectatorVoiceRemove(rt, userId, in);
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
        if (rt.tournament) {
            sendSnapshot(rt, userId);
            sendPhase(rt, userId);
            return championships.reconnectStatus(rt.roomId)
                    .doOnNext(status -> rt.tellUser(userId, Envelope.of(MessageType.EVENT,
                            Map.of("type", "RECONNECT_WAIT", "data", status)))).then();
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
                .zipWith(members.findByRoomId(rt.roomId)
                        .concatMap(m -> users.findById(m.userId())
                                .map(u -> lobbyMemberPayload(m, u.isBot(), u.avatarUrl()))
                                .defaultIfEmpty(lobbyMemberPayload(m, false, null)))
                        .collectList())
                .doOnNext(t -> {
                    RoomRow room = t.getT1();
                    Map<String, Object> payload = new LinkedHashMap<>();
                    payload.put("lobby", true);
                    payload.put("roomId", room.id().toString());
                    payload.put("code", room.code());
                    payload.put("hostId", room.hostId().toString());
                    payload.put("status", room.status());
                    if ("goosi".equals(room.gameType())) {
                        payload.put("mode", goosiConfigFrom(room.gameConfig()).mode());
                    }
                    payload.put("members", t.getT2());
                    payload.put("spectatorCount", rt.spectatorUserIds.size());
                    rt.tellUser(userId, Envelope.of(MessageType.SNAPSHOT, payload));
                })
                .then();
    }

    private Map<String, Object> lobbyMemberPayload(RoomMemberRow member, boolean isBot, String avatarUrl) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("userId", member.userId().toString());
        payload.put("nickname", member.nickname() == null ? "" : member.nickname());
        payload.put("ready", member.readyState());
        payload.put("connectionStatus", member.connectionStatus());
        payload.put("isBot", isBot);
        payload.put("avatarUrl", avatarUrl == null ? "" : avatarUrl);
        return payload;
    }

    /**
     * Re-sends each connected player their own view, for the games that keep
     * something private per player (see {@link GameModule#hasPrivatePlayerState}).
     *
     * <p>Whot is the case this exists for: your hand changes when you play,
     * and again when someone else sends you to market, so the public frame
     * alone leaves every client's hand stale. Spectators are skipped — they
     * get the public broadcast, which is the whole point of not being dealt in.
     */
    private void broadcastPrivateState(RoomRuntime rt) {
        if (!rt.started() || !rt.module().hasPrivatePlayerState()) {
            return;
        }
        for (String userId : rt.connectedUserIds) {
            if (!rt.spectatorUserIds.contains(userId)) {
                sendSnapshot(rt, userId);
            }
        }
    }

    private void broadcastSpectatorState(RoomRuntime rt) {
        for (String userId : rt.spectatorUserIds) {
            sendSnapshot(rt, userId);
        }
    }

    private void sendSnapshot(RoomRuntime rt, String userId) {
        rt.tellUser(userId, Envelope.of(MessageType.SNAPSHOT,
                snapshotView(rt, userId, rt.spectatorUserIds.contains(userId))));
    }

    private Map<String, Object> snapshotView(RoomRuntime rt, String userId, boolean spectator) {
        Map<String, Object> view = new LinkedHashMap<>(spectator
                ? rt.module().broadcastState(rt.state()).data()
                : rt.module().visibleStateFor(rt.state(), userId).data());
        view.put("lobby", false);
        // Generic, game-agnostic fields — every screen gets these regardless of
        // which GameModule is running, so a late joiner/reconnect (player or
        // spectator) immediately knows the room is paused and how many are watching.
        view.put("paused", rt.paused);
        view.put("secondsLeft", secondsLeft(rt));
        view.put("spectatorCount", rt.spectatorUserIds.size());
        view.put("spectatorsMuted", rt.spectatorsMuted);
        view.put("connectedPlayers", List.copyOf(rt.connectedUserIds));
        view.put("spectatorVoiceRequests", List.copyOf(rt.spectatorVoiceRequests));
        view.put("spectatorVoiceSpeakers", List.copyOf(rt.spectatorVoiceSpeakers));
        view.put("mutedSpectatorVoiceSpeakers", List.copyOf(rt.mutedSpectatorVoiceSpeakers));
        return view;
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
                .flatMap(m -> members.save(new RoomMemberRow(m.id(), m.roomId(), m.userId(), m.nickname(),
                        m.connectionStatus(), ready, m.botDifficulty(), m.joinedAt())))
                .then(broadcastLobby(rt, "READY_CHANGED", Map.of("userId", userId, "ready", ready)));
    }

    /**
     * {@code spectate} is the always-open audience channel — available in the
     * lobby and mid-game, in every game type, from players and spectators
     * alike (TikTok-style comments). {@code table}/{@code traitors} stay
     * TrueArena's discussion-phase-only, role-gated channels — see
     * {@link ChatMessage}. Rejects (rather than silently drops) a bad send so
     * the client can tell the sender why nothing sent, same as any other
     * {@code ERROR}.
     */
    private Mono<Void> handleChat(RoomRuntime rt, String userId, Envelope in, boolean spectator) {
        String channel = String.valueOf(in.payload().get("channel"));
        if (spectator && !ChatMessage.SPECTATE.equals(channel)) {
            return tellError(rt, userId, "SPECTATOR_READ_ONLY", "spectators can comment on the spectator channel");
        }
        if (ChatMessage.AGENT.equals(channel)) {
            // Only a bot may speak as a bot. Checked server-side rather than
            // trusted from the client so the badge in the UI means something.
            return users.findById(UUID.fromString(userId))
                    .flatMap(u -> u.isBot()
                            ? emitChat(rt, userId, channel, in)
                            : tellError(rt, userId, "NOT_AN_AGENT", "only Cyber Agents talk on this channel"));
        }
        if (ChatMessage.SPECTATE.equals(channel)) {
            if (rt.spectatorsMuted) {
                return tellError(rt, userId, "SPECTATORS_MUTED", "the players have muted spectator chat");
            }
            return emitChat(rt, userId, channel, in);
        }
        if (!ChatMessage.TABLE.equals(channel) && !ChatMessage.TRAITORS.equals(channel)) {
            return tellError(rt, userId, "BAD_CHANNEL", "channel must be 'table', 'traitors', 'spectate' or 'agent'");
        }
        if (!rt.started()) {
            return tellError(rt, userId, "NOT_STARTED", "the game hasn't started yet");
        }
        // The round-table restriction belongs to games that actually have a
        // round table. Traitors gates table talk to that phase on purpose;
        // Draughts, Goosi and Word Bluff have no such phase, and blanket-
        // applying the rule left them with no way for players to talk at all.
        boolean hasRoundTable = rt.module().definePhases(rt.config).stream()
                .anyMatch(p -> "RoundTable".equals(p.name()));
        if (hasRoundTable && !"RoundTable".equals(rt.state().phase())) {
            return tellError(rt, userId, "WRONG_PHASE", "that channel is only open during the round table");
        }
        if (ChatMessage.TRAITORS.equals(channel) && !roleGroupMatches("traitor", String.valueOf(rt.roleByUser().get(userId)))) {
            return tellError(rt, userId, "NOT_TRAITOR", "only traitors can use that channel");
        }
        return emitChat(rt, userId, channel, in);
    }

    private Mono<Void> emitChat(RoomRuntime rt, String userId, String channel, Envelope in) {
        Object rawText = in.payload().get("text");
        String text = rawText == null ? "" : rawText.toString().strip();
        if (text.isEmpty()) {
            return tellError(rt, userId, "EMPTY_MESSAGE", "message can't be empty");
        }
        if (text.length() > 240) {
            text = text.substring(0, 240);
        }
        rt.bus.tryEmitNext(new ChatMessage(channel, userId, text, System.currentTimeMillis()));
        return Mono.empty();
    }

    /**
     * Pausing is a room/transport concern, not game business logic — it lives
     * here rather than as a {@code PLAYER_ACTION} so it works uniformly for
     * every {@code GameModule} without each one needing to know about it.
     * Spectators (never in {@link RoomRuntime#connectedUserIds}) can't toggle
     * it; either connected player can.
     */
    private Mono<Void> handlePauseToggle(RoomRuntime rt, String userId) {
        if (rt.tournament) return tellError(rt, userId, "TOURNAMENT_CLOCK", "the tournament controls the game clock");
        if (championships != null) {
            return championships.isTournamentRoom(rt.roomId).flatMap(tournament -> tournament
                    ? tellError(rt, userId, "TOURNAMENT_CLOCK", "the tournament controls the game clock")
                    : togglePause(rt, userId));
        }
        return togglePause(rt, userId);
    }

    private Mono<Void> togglePause(RoomRuntime rt, String userId) {
        if (!rt.started()) {
            return tellError(rt, userId, "NOT_STARTED", "the game hasn't started yet");
        }
        if (!rt.connectedUserIds.contains(userId)) {
            return tellError(rt, userId, "SPECTATORS_CANT_PAUSE", "only players can pause the game");
        }
        rt.paused = !rt.paused;
        if (rt.paused) {
            freezeTimer(rt);
        } else {
            thawTimer(rt);
        }
        rt.bus.tryEmitNext(new LobbyBroadcast(
                rt.paused ? "GAME_PAUSED" : "GAME_RESUMED",
                Map.of("by", userId, "secondsLeft", secondsLeft(rt))));
        return Mono.empty();
    }

    /**
     * Any player (not just the host) can mute the always-open spectate
     * channel — spectators can watch regardless, they just lose the
     * TikTok-style comment stream while it's muted. Broadcast so a
     * spectator's own client can grey out its input immediately rather than
     * finding out only when a send comes back as an error.
     */
    private Mono<Void> handleMuteSpectatorsToggle(RoomRuntime rt, String userId) {
        if (!rt.connectedUserIds.contains(userId)) {
            return tellError(rt, userId, "SPECTATORS_CANT_MUTE", "only players can mute spectator chat");
        }
        rt.spectatorsMuted = !rt.spectatorsMuted;
        rt.bus.tryEmitNext(new LobbyBroadcast(
                rt.spectatorsMuted ? "SPECTATORS_MUTED" : "SPECTATORS_UNMUTED", Map.of("by", userId)));
        return Mono.empty();
    }

    private Mono<Void> handleSpectatorVoiceRequest(RoomRuntime rt, String userId, boolean spectator) {
        if (!spectator || !rt.spectatorUserIds.contains(userId)) {
            return tellError(rt, userId, "PLAYERS_ALREADY_ALLOWED", "players can join game voice directly");
        }
        if (!rt.started() || rt.state().finished()) {
            return tellError(rt, userId, "NO_ACTIVE_GAME", "live talk is only available during a game");
        }
        if (rt.spectatorVoiceSpeakers.contains(userId)) {
            return tellError(rt, userId, "ALREADY_APPROVED", "you are already approved for live talk");
        }
        if (rt.spectatorVoiceRequests.add(userId)) {
            rt.bus.tryEmitNext(new LobbyBroadcast("SPECTATOR_VOICE_REQUESTED", Map.of("userId", userId)));
        }
        return Mono.empty();
    }

    private Mono<Void> handleSpectatorVoiceApprove(RoomRuntime rt, String playerId, Envelope in) {
        if (!rt.connectedUserIds.contains(playerId)) {
            return tellError(rt, playerId, "PLAYERS_ONLY", "only active players can approve live talk");
        }
        String spectatorId = voiceTarget(in);
        if (spectatorId == null || !rt.spectatorUserIds.contains(spectatorId)) {
            return tellError(rt, playerId, "NO_SUCH_SPECTATOR", "that spectator is no longer watching");
        }
        rt.spectatorVoiceRequests.remove(spectatorId);
        rt.mutedSpectatorVoiceSpeakers.remove(spectatorId);
        rt.spectatorVoiceSpeakers.add(spectatorId);
        rt.bus.tryEmitNext(new LobbyBroadcast("SPECTATOR_VOICE_APPROVED", Map.of(
                "userId", spectatorId, "by", playerId)));
        return setVoicePublish(rt, spectatorId, true);
    }

    private Mono<Void> handleSpectatorVoiceDecline(RoomRuntime rt, String playerId, Envelope in) {
        if (!rt.connectedUserIds.contains(playerId)) {
            return tellError(rt, playerId, "PLAYERS_ONLY", "only active players can decline live talk");
        }
        String spectatorId = voiceTarget(in);
        if (spectatorId == null || !rt.spectatorVoiceRequests.remove(spectatorId)) {
            return tellError(rt, playerId, "NO_VOICE_REQUEST", "that live-talk request is no longer pending");
        }
        rt.bus.tryEmitNext(new LobbyBroadcast("SPECTATOR_VOICE_DECLINED", Map.of(
                "userId", spectatorId, "by", playerId)));
        return Mono.empty();
    }

    private Mono<Void> handleSpectatorVoiceMuteToggle(RoomRuntime rt, String playerId, Envelope in) {
        if (!rt.connectedUserIds.contains(playerId)) {
            return tellError(rt, playerId, "PLAYERS_ONLY", "only active players can mute live speakers");
        }
        String spectatorId = voiceTarget(in);
        if (spectatorId == null || !rt.spectatorVoiceSpeakers.contains(spectatorId)) {
            return tellError(rt, playerId, "NOT_A_LIVE_SPEAKER", "that spectator is not in live talk");
        }
        boolean muted;
        if (rt.mutedSpectatorVoiceSpeakers.remove(spectatorId)) {
            muted = false;
        } else {
            rt.mutedSpectatorVoiceSpeakers.add(spectatorId);
            muted = true;
        }
        rt.bus.tryEmitNext(new LobbyBroadcast(
                muted ? "SPECTATOR_VOICE_MUTED" : "SPECTATOR_VOICE_UNMUTED",
                Map.of("userId", spectatorId, "by", playerId)));
        return setVoicePublish(rt, spectatorId, !muted);
    }

    private Mono<Void> handleSpectatorVoiceRemove(RoomRuntime rt, String playerId, Envelope in) {
        if (!rt.connectedUserIds.contains(playerId)) {
            return tellError(rt, playerId, "PLAYERS_ONLY", "only active players can remove live speakers");
        }
        String spectatorId = voiceTarget(in);
        if (spectatorId == null || !rt.spectatorVoiceSpeakers.remove(spectatorId)) {
            return tellError(rt, playerId, "NOT_A_LIVE_SPEAKER", "that spectator is not in live talk");
        }
        rt.spectatorVoiceRequests.remove(spectatorId);
        rt.mutedSpectatorVoiceSpeakers.remove(spectatorId);
        rt.bus.tryEmitNext(new LobbyBroadcast("SPECTATOR_VOICE_REMOVED", Map.of(
                "userId", spectatorId, "by", playerId)));
        return removeFromVoice(rt, spectatorId);
    }

    private String voiceTarget(Envelope in) {
        Object value = in.payload().get("userId");
        if (value == null) return null;
        try {
            return UUID.fromString(value.toString()).toString();
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    private Mono<Void> setVoicePublish(RoomRuntime rt, String userId, boolean canPublish) {
        if (voiceAdmin == null) return Mono.empty();
        return voiceAdmin.setCanPublish("game-" + rt.roomId, userId, canPublish)
                .onErrorResume(error -> {
                    log.warn("could not update game voice permission for room {} user {}: {}",
                            rt.roomId, userId, error.toString());
                    return Mono.empty();
                });
    }

    private Mono<Void> removeFromVoice(RoomRuntime rt, String userId) {
        if (voiceAdmin == null) return Mono.empty();
        return voiceAdmin.remove("game-" + rt.roomId, userId)
                .onErrorResume(error -> {
                    log.warn("could not remove game voice participant for room {} user {}: {}",
                            rt.roomId, userId, error.toString());
                    return Mono.empty();
                });
    }

    // ---------------------------------------------------------------- game start / actions

    private Mono<Void> handleGameStart(RoomRuntime rt, String userId, Map<String, Object> options) {
        if (championships != null) {
            return championships.isTournamentRoom(rt.roomId).flatMap(tournament -> tournament
                    ? tellError(rt, userId, "TOURNAMENT_START", "the championship starts this match automatically")
                    : startOrdinaryGame(rt, userId, options));
        }
        return startOrdinaryGame(rt, userId, options);
    }

    private Mono<Void> startOrdinaryGame(RoomRuntime rt, String userId, Map<String, Object> options) {
        if (!userId.equals(rt.hostUserId)) {
            return tellError(rt, userId, "NOT_HOST", "only the host can start the game");
        }
        if (rt.started()) {
            return tellError(rt, userId, "ALREADY_STARTED", "this huud's game is already running");
        }
        return lock.withLock(rt.roomId, LOCK_TTL, () -> rooms.findById(rt.roomId)
                .switchIfEmpty(Mono.error(new IllegalStateException("room not found")))
                .zipWith(members.findByRoomId(rt.roomId).collectList())
                .flatMap(t -> {
                    String gameType = t.getT1().gameType();
                    List<String> playerIds = t.getT2().stream().map(m -> m.userId().toString()).toList();
                    return switch (gameType) {
                        case "wordbluff" -> startWordBluff(rt, userId, playerIds);
                        case "draughts" -> startDraughts(rt, userId, playerIds);
                        case "goosi" -> startGoosi(rt, userId, playerIds);
                        case "whot" -> startWhot(rt, userId, playerIds);
                        case "ludo" -> startLudo(rt, userId, playerIds, options);
                        default -> startTrueArena(rt, userId, playerIds, t.getT1().gameConfig());
                    };
                }));
    }

    private Mono<Void> startTrueArena(RoomRuntime rt, String userId, List<String> playerIds, String roomConfig) {
        GameConfig cfg;
        try {
            cfg = withPlayers(roomConfig == null || roomConfig.isBlank()
                    ? Presets.CLASSIC_CONSPIRACY.config()
                    : mapper.readValue(roomConfig, GameConfig.class), playerIds.size());
        } catch (Exception e) {
            return tellError(rt, userId, "BAD_CONFIG", "the selected game rules could not be read");
        }
        ConfigValidator.Result validation = ConfigValidator.validate(cfg);
        if (!validation.ok()) {
            return tellError(rt, userId, "BAD_CONFIG", String.join("; ", validation.errors()));
        }

        TrueArenaModule module = new TrueArenaModule();
        long seed = ThreadLocalRandom.current().nextLong();
        GameState state;
        try {
            state = module.initialState(playerIds, cfg, RandomSource.seeded(seed));
        } catch (RuleViolation rv) {
            return tellError(rt, userId, rv.code(), rv.getMessage());
        }

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
    }

    private Mono<Void> startWordBluff(RoomRuntime rt, String userId, List<String> playerIds) {
        WordBluffConfig cfg = WordBluffConfig.defaults();
        WordBluffModule module = new WordBluffModule();
        long seed = ThreadLocalRandom.current().nextLong();
        GameState state;
        try {
            state = module.initialState(playerIds, cfg, RandomSource.seeded(seed));
        } catch (RuleViolation rv) {
            return tellError(rt, userId, rv.code(), rv.getMessage());
        }

        // Word Bluff has no catalog versioning and no roles table entries — teams
        // aren't secret roles, they're plain public state (see commonView).
        return sessions.save(GameSessionRow.start(rt.roomId, module.gameType(), writeJson(cfg), 1, seed))
                .flatMap(session -> {
                    rt.config = cfg;
                    rt.start(module, state, session.id());
                    return updateRoomStatus(rt.roomId, "in_game")
                            .then(afterMutation(rt, state.events()));
                });
    }

    private Mono<Void> startDraughts(RoomRuntime rt, String userId, List<String> playerIds) {
        return rooms.findById(rt.roomId)
                .map(room -> draughtsConfigFrom(room.gameConfig()))
                .defaultIfEmpty(DraughtsConfig.defaults())
                .flatMap(cfg -> startDraughtsWith(rt, userId, playerIds, cfg));
    }

    /** Host-chosen Draughts options; anything missing or unreadable falls back to the defaults. */
    private DraughtsConfig draughtsConfigFrom(String json) {
        if (json == null || json.isBlank()) {
            return DraughtsConfig.defaults();
        }
        try {
            Map<?, ?> raw = mapper.readValue(json, Map.class);
            DraughtsConfig defaults = DraughtsConfig.defaults();
            int turnSeconds = raw.get("turnSeconds") instanceof Number n ? n.intValue() : defaults.turnSeconds();
            // Missing rules use the casual default. An explicit true keeps
            // compulsory captures available for hosts who choose them.
            boolean mandatory = Boolean.TRUE.equals(raw.get("mandatoryCapture"));
            return new DraughtsConfig(turnSeconds, mandatory);
        } catch (Exception e) {
            log.warn("unreadable draughts config, using defaults: {}", e.toString());
            return DraughtsConfig.defaults();
        }
    }

    private Mono<Void> startDraughtsWith(RoomRuntime rt, String userId, List<String> playerIds, DraughtsConfig cfg) {
        DraughtsModule module = new DraughtsModule();
        long seed = ThreadLocalRandom.current().nextLong();
        GameState state;
        try {
            state = module.initialState(playerIds, cfg, RandomSource.seeded(seed));
        } catch (RuleViolation rv) {
            return tellError(rt, userId, rv.code(), rv.getMessage());
        }

        // Draughts has nothing secret either — same reasoning as Word Bluff:
        // no catalog versioning, no roles table entries.
        return sessions.save(GameSessionRow.start(rt.roomId, module.gameType(), writeJson(cfg), 1, seed))
                .flatMap(session -> {
                    rt.config = cfg;
                    rt.start(module, state, session.id());
                    return updateRoomStatus(rt.roomId, "in_game")
                            .then(afterMutation(rt, state.events()));
                });
    }

    /** Starts a bracket pairing with its phase clock suspended until both players connect. */
    public Mono<Void> startTournamentRoom(UUID roomId) {
        return ensureRuntime(roomId).flatMap(rt -> lock.withLock(roomId, LOCK_TTL, () -> {
            if (rt.started()) return Mono.empty();
            rt.tournament = true;
            rt.paused = true;
            return members.findByRoomId(roomId).map(m -> m.userId().toString()).sort().collectList()
                    .flatMap(players -> {
                        if (players.size() != 2)
                            return Mono.error(new IllegalStateException("tournament pairing must have two players"));
                        return sessions.findFirstByRoomIdOrderByStartedAtDesc(roomId)
                                .flatMap(session -> restoreTournamentRoom(rt, players, session).thenReturn(true))
                                .defaultIfEmpty(false)
                                .flatMap(restored -> restored ? Mono.empty()
                                        : startDraughtsWith(rt, rt.hostUserId, players, DraughtsConfig.defaults()));
                    });
        }));
    }

    private Mono<Void> restoreTournamentRoom(RoomRuntime rt, List<String> players, GameSessionRow session) {
        DraughtsModule module = new DraughtsModule();
        DraughtsConfig cfg = draughtsConfigFrom(session.config().asString());
        return championships.savedActions(session.id()).collectList().flatMap(actions -> Mono.fromCallable(() -> {
            GameState state = module.initialState(players, cfg, RandomSource.seeded(session.rngSeed()));
            GameRunner runner = new GameRunner(module);
            for (var action : actions) {
                if ("__ELAPSE".equals(action.type())) {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> data = mapper.readValue(action.payload(), Map.class);
                    state = runner.elapse(state, String.valueOf(data.get("phase"))).state();
                } else {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> data = mapper.readValue(action.payload(), Map.class);
                    state = runner.apply(state, new PlayerAction(action.actionId(), action.actor().toString(),
                            action.type(), data)).state();
                }
            }
            rt.config = cfg;
            rt.start(module, state, session.id());
            rescheduleTimer(rt);
            return state;
        }).flatMap(state -> championships.savedClock(rt.roomId)
                .doOnNext(clock -> {
                    if (clock.phase().equals(state.phase()) && !state.finished())
                        rt.timerRemainingMs = Math.max(1000, clock.remainingMs());
                }).thenReturn(state)).doOnNext(state -> {
            for (String connected : rt.connectedUserIds) sendSnapshot(rt, connected);
            for (String spectator : rt.spectatorUserIds) sendSnapshot(rt, spectator);
            broadcastPhase(rt);
        }).flatMap(state -> {
            if (!state.finished()) return Mono.empty();
            return resultRows.findByGameSessionId(session.id()).hasElement()
                    .flatMap(saved -> saved
                            ? championships.gameFinished(rt.roomId, session.id(),
                                    module.checkWinCondition(state).orElseThrow().perPlayerOutcome())
                            : finishGame(rt));
        }));
    }

    /** Reconnect policy is decided by the tournament service, never by the client. */
    public Mono<Void> setTournamentPaused(UUID roomId, boolean pause) {
        return ensureRuntime(roomId).flatMap(rt -> lock.withLock(roomId, LOCK_TTL, () -> {
            if (!rt.started() || rt.state().finished() || rt.paused == pause) return Mono.empty();
            rt.paused = pause;
            if (pause) freezeTimer(rt); else thawTimer(rt);
            rt.bus.tryEmitNext(new LobbyBroadcast(pause ? "GAME_PAUSED" : "GAME_RESUMED",
                    Map.of("reason", "reconnect", "secondsLeft", secondsLeft(rt))));
            return persistTournamentClock(roomId);
        }));
    }

    public Mono<Void> persistTournamentClock(UUID roomId) {
        return registry.find(roomId).map(rt -> {
            if (!rt.tournament || !rt.started() || rt.state().finished()) return Mono.<Void>empty();
            long remaining = rt.paused ? rt.timerRemainingMs
                    : Math.max(0, rt.timerDeadlineMs - System.currentTimeMillis());
            return championships.recordClock(roomId, rt.state().phase(), remaining);
        }).orElseGet(Mono::empty);
    }

    public Mono<Void> forfeitTournamentRoom(UUID roomId, UUID loser) {
        return ensureRuntime(roomId).flatMap(rt -> lock.withLock(roomId, LOCK_TTL, () -> {
            if (!rt.started() || rt.state().finished())
                return Mono.empty();
            String opponent = rt.module().broadcastState(rt.state()).data().get("playerA").toString().equals(loser.toString())
                    ? rt.module().broadcastState(rt.state()).data().get("playerB").toString()
                    : rt.module().broadcastState(rt.state()).data().get("playerA").toString();
            if (!rt.connectedUserIds.contains(opponent)) return Mono.empty();
            return championships.forfeitAllowed(roomId, loser).flatMap(allowed -> {
                if (!allowed) return Mono.empty();
                String actionId = UUID.randomUUID().toString();
                GameRunner.Step step = new GameRunner(rt.module()).apply(rt.state(),
                        new PlayerAction(actionId, loser.toString(), "FORFEIT", Map.of()));
                return championships.recordAction(roomId, rt.gameSessionId, actionId, loser, "FORFEIT", "{}")
                        .then(Mono.defer(() -> {
                            rt.setState(step.state());
                            return afterMutation(rt, step.events());
                        }));
            });
        }));
    }

    /** End an ordinary Draft match against a Cyber Agent before its socket closes. */
    public Mono<Boolean> forfeitBotDraughtsRoom(UUID roomId, UUID loser) {
        return registry.find(roomId)
                .<Mono<Boolean>>map(rt -> lock.withLock(roomId, LOCK_TTL, () -> {
                    if (rt.tournament || !rt.started() || rt.state().finished()
                            || !"draughts".equals(rt.module().gameType())) {
                        return Mono.just(false);
                    }
                    GameRunner.Step step = new GameRunner(rt.module()).apply(rt.state(),
                            new PlayerAction(UUID.randomUUID().toString(), loser.toString(), "FORFEIT", Map.of()));
                    rt.setState(step.state());
                    return afterMutation(rt, step.events()).thenReturn(true);
                }))
                .orElseGet(() -> Mono.just(false));
    }

    /** Settle an ordinary Whot table whose only remaining opponents are the host's agents. */
    public Mono<Boolean> forfeitBotWhotRoom(UUID roomId, UUID loser) {
        return registry.find(roomId)
                .<Mono<Boolean>>map(rt -> lock.withLock(roomId, LOCK_TTL, () -> {
                    if (rt.tournament || !rt.started() || rt.state().finished()
                            || !"whot".equals(rt.module().gameType())) {
                        return Mono.just(false);
                    }
                    GameRunner.Step step = new GameRunner(rt.module()).apply(rt.state(),
                            new PlayerAction(UUID.randomUUID().toString(), loser.toString(), "FORFEIT", Map.of()));
                    if (!step.state().finished()) return Mono.just(false);
                    rt.setState(step.state());
                    return afterMutation(rt, step.events()).thenReturn(true);
                }))
                .orElseGet(() -> Mono.just(false));
    }

    /** Forfeit a Ludo seat even when it is another player's turn. */
    public Mono<Boolean> forfeitLudoRoom(UUID roomId, UUID loser) {
        return registry.find(roomId)
                .<Mono<Boolean>>map(rt -> lock.withLock(roomId, LOCK_TTL, () -> {
                    if (!rt.started() || rt.state().finished() || !"ludo".equals(rt.module().gameType())) {
                        return Mono.just(false);
                    }
                    try {
                        GameRunner.Step step = new GameRunner(rt.module()).apply(rt.state(),
                                new PlayerAction(UUID.randomUUID().toString(), loser.toString(), "FORFEIT", Map.of()));
                        rt.setState(step.state());
                        return afterMutation(rt, step.events()).thenReturn(true);
                    } catch (RuleViolation ignored) {
                        return Mono.just(false);
                    }
                })).orElseGet(() -> Mono.just(false));
    }

    /** End an ordinary Oware pit against a Cyber Agent before its socket closes. */
    public Mono<Boolean> forfeitBotGoosiRoom(UUID roomId, UUID loser) {
        return registry.find(roomId)
                .<Mono<Boolean>>map(rt -> lock.withLock(roomId, LOCK_TTL, () -> {
                    if (rt.tournament || !rt.started() || rt.state().finished()
                            || !"goosi".equals(rt.module().gameType())) {
                        return Mono.just(false);
                    }
                    GameRunner.Step step = new GameRunner(rt.module()).apply(rt.state(),
                            new PlayerAction(UUID.randomUUID().toString(), loser.toString(), "RESIGN", Map.of()));
                    rt.setState(step.state());
                    return afterMutation(rt, step.events()).thenReturn(true);
                }))
                .orElseGet(() -> Mono.just(false));
    }

    /** End an ordinary Word Bluff round against a Cyber Agent before its socket closes. */
    public Mono<Boolean> forfeitBotWordBluffRoom(UUID roomId, UUID loser) {
        return registry.find(roomId)
                .<Mono<Boolean>>map(rt -> lock.withLock(roomId, LOCK_TTL, () -> {
                    if (rt.tournament || !rt.started() || rt.state().finished()
                            || !"wordbluff".equals(rt.module().gameType())) {
                        return Mono.just(false);
                    }
                    GameRunner.Step step = new GameRunner(rt.module()).apply(rt.state(),
                            new PlayerAction(UUID.randomUUID().toString(), loser.toString(), "FORFEIT", Map.of()));
                    rt.setState(step.state());
                    return afterMutation(rt, step.events()).thenReturn(true);
                }))
                .orElseGet(() -> Mono.just(false));
    }

    public Mono<Void> closeTournamentRoom(UUID roomId) {
        return ensureRuntime(roomId).flatMap(rt -> lock.withLock(roomId, LOCK_TTL, () -> {
            rt.paused = true;
            rt.cancelTimer();
            return updateRoomStatus(roomId, "ended");
        }));
    }

    private Mono<Void> startGoosi(RoomRuntime rt, String userId, List<String> playerIds) {
        return rooms.findById(rt.roomId)
                .map(room -> goosiConfigFrom(room.gameConfig()))
                .defaultIfEmpty(GoosiConfig.defaults())
                .flatMap(cfg -> startGoosiWith(rt, userId, playerIds, cfg));
    }

    /**
     * Host-chosen Goosi options — the same per-room config Draughts reads
     * (see {@link #draughtsConfigFrom}); anything missing or unreadable
     * falls back to the defaults.
     */
    private GoosiConfig goosiConfigFrom(String json) {
        if (json == null || json.isBlank()) {
            return GoosiConfig.defaults();
        }
        try {
            Map<?, ?> raw = mapper.readValue(json, Map.class);
            GoosiConfig defaults = GoosiConfig.defaults();
            int seedsPerPit = raw.get("seedsPerPit") instanceof Number n ? n.intValue() : defaults.seedsPerPit();
            int turnSeconds = raw.get("turnSeconds") instanceof Number n ? n.intValue() : defaults.turnSeconds();
            String mode = raw.get("mode") instanceof String value ? value : defaults.mode();
            return new GoosiConfig(seedsPerPit, turnSeconds, mode);
        } catch (Exception e) {
            log.warn("unreadable goosi config, using defaults: {}", e.toString());
            return GoosiConfig.defaults();
        }
    }

    private Mono<Void> startGoosiWith(RoomRuntime rt, String userId, List<String> playerIds, GoosiConfig cfg) {
        GoosiModule module = new GoosiModule();
        long seed = ThreadLocalRandom.current().nextLong();
        GameState state;
        try {
            state = module.initialState(playerIds, cfg, RandomSource.seeded(seed));
        } catch (RuleViolation rv) {
            return tellError(rt, userId, rv.code(), rv.getMessage());
        }

        // Goosi has nothing secret either — same reasoning as Draughts/Word Bluff.
        return sessions.save(GameSessionRow.start(rt.roomId, module.gameType(), writeJson(cfg), 1, seed))
                .flatMap(session -> {
                    rt.config = cfg;
                    rt.start(module, state, session.id());
                    return updateRoomStatus(rt.roomId, "in_game")
                            .then(afterMutation(rt, state.events()));
                });
    }

    private Mono<Void> startWhot(RoomRuntime rt, String userId, List<String> playerIds) {
        return rooms.findById(rt.roomId)
                .map(room -> whotConfigFrom(room.gameConfig()))
                .defaultIfEmpty(WhotConfig.defaults())
                .flatMap(cfg -> startWhotWith(rt, userId, playerIds, cfg));
    }

    private Mono<Void> startLudo(RoomRuntime rt, String userId, List<String> playerIds,
                                 Map<String, Object> options) {
        Object requested = options.get("twoPlayerPieces");
        if (playerIds.size() == 2 && requested != null
                && (!(requested instanceof Number n) || (n.doubleValue() != 4 && n.doubleValue() != 8))) {
            return tellError(rt, userId, "BAD_CONFIG", "choose four or eight Ludo pieces");
        }
        return rooms.findById(rt.roomId).map(room -> {
            Map<?, ?> raw;
            try {
                raw = room.gameConfig() == null ? Map.of() : mapper.readValue(room.gameConfig(), Map.class);
            } catch (Exception e) {
                raw = Map.of();
            }
            int storedPieces = raw.get("twoPlayerPieces") instanceof Number n ? n.intValue() : 4;
            int chosenPieces = playerIds.size() == 2
                    ? requested instanceof Number n ? n.intValue() : storedPieces
                    : 4;
            int turnSeconds = raw.get("turnSeconds") instanceof Number n ? n.intValue() : 60;
            try {
                return new LudoConfig(turnSeconds, chosenPieces);
            } catch (IllegalArgumentException e) {
                return new LudoConfig(60, requested instanceof Number n ? n.intValue() : 4);
            }
        }).defaultIfEmpty(LudoConfig.defaults()).flatMap(cfg -> {
            LudoModule module = new LudoModule();
            long seed = ThreadLocalRandom.current().nextLong();
            GameState state;
            try {
                state = module.initialState(playerIds, cfg, RandomSource.seeded(seed));
            } catch (RuleViolation violation) {
                return tellError(rt, userId, violation.code(), violation.getMessage());
            }
            return sessions.save(GameSessionRow.start(rt.roomId, module.gameType(), writeJson(cfg), 1, seed))
                    .flatMap(session -> {
                        rt.config = cfg;
                        rt.start(module, state, session.id());
                        return updateRoomStatus(rt.roomId, "in_game").then(afterMutation(rt, state.events()));
                    });
        });
    }

    /**
     * Host-chosen Whot options. Every special card is a switch here because
     * tables genuinely disagree about them — whether a 2 can be stacked back,
     * whether Whot itself is even in the deck — and the house rules are
     * settled before the deal, not argued about mid-game. All default on.
     */
    private WhotConfig whotConfigFrom(String json) {
        if (json == null || json.isBlank()) {
            return WhotConfig.defaults();
        }
        try {
            Map<?, ?> raw = mapper.readValue(json, Map.class);
            WhotConfig d = WhotConfig.defaults();
            return new WhotConfig(
                    raw.get("turnSeconds") instanceof Number n ? n.intValue() : d.turnSeconds(),
                    raw.get("startingHand") instanceof Number n ? n.intValue() : d.startingHand(),
                    raw.get("includeWhot") instanceof Boolean b ? b : d.includeWhot(),
                    raw.get("pickTwo") instanceof Boolean b ? b : d.pickTwo(),
                    raw.get("pickTwoStacking") instanceof Boolean b ? b : d.pickTwoStacking(),
                    raw.get("generalMarket") instanceof Boolean b ? b : d.generalMarket(),
                    raw.get("holdOn") instanceof Boolean b ? b : d.holdOn(),
                    raw.get("suspension") instanceof Boolean b ? b : d.suspension(),
                    raw.get("mode") instanceof String mode ? mode : d.mode(),
                    raw.get("tellRule") instanceof String rule ? rule : d.tellRule(),
                    raw.get("tellMinCards") instanceof Number minimum ? minimum.intValue() : d.tellMinCards());
        } catch (Exception e) {
            log.warn("unreadable whot config, using defaults: {}", e.toString());
            return WhotConfig.defaults();
        }
    }

    private Mono<Void> startWhotWith(RoomRuntime rt, String userId, List<String> playerIds, WhotConfig cfg) {
        if (cfg.tell()) {
            return Flux.fromIterable(playerIds)
                    .concatMap(id -> users.findById(UUID.fromString(id)))
                    .any(UserRow::isBot)
                    .flatMap(hasBot -> hasBot
                            ? tellError(rt, userId, "TELL_NEEDS_PLAYERS", "The Tell needs human teammates for private signals")
                            : startWhotGame(rt, userId, playerIds, cfg));
        }
        return startWhotGame(rt, userId, playerIds, cfg);
    }

    private Mono<Void> startWhotGame(RoomRuntime rt, String userId, List<String> playerIds, WhotConfig cfg) {
        WhotModule module = new WhotModule();
        long seed = ThreadLocalRandom.current().nextLong();
        GameState state;
        try {
            state = module.initialState(playerIds, cfg, RandomSource.seeded(seed));
        } catch (RuleViolation rv) {
            return tellError(rt, userId, rv.code(), rv.getMessage());
        }

        // Unlike the board games, Whot does hold something back per player —
        // their hand — which rides the per-player snapshot, never the public
        // broadcast (see broadcastPrivateState).
        return sessions.save(GameSessionRow.start(rt.roomId, module.gameType(), writeJson(cfg), 1, seed))
                .flatMap(session -> {
                    rt.config = cfg;
                    rt.start(module, state, session.id());
                    return updateRoomStatus(rt.roomId, "in_game")
                            .then(afterMutation(rt, state.events()));
                });
    }

    private Mono<Void> handlePlayerAction(RoomRuntime rt, String userId, Envelope in) {
        if (!rt.started()) {
            return tellError(rt, userId, "NOT_STARTED", "this huud hasn't started a game yet");
        }
        if (rt.state().finished()) {
            return tellError(rt, userId, "ALREADY_FINISHED", "this game has ended");
        }
        if (rt.tournament && rt.paused) {
            return tellError(rt, userId, "MATCH_PAUSED", "waiting for both players to reconnect");
        }
        String action = String.valueOf(in.payload().get("action"));
        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) in.payload().getOrDefault("data", Map.of());
        Object rawActionId = in.payload().get("actionId");
        String actionId = rawActionId != null ? rawActionId.toString() : UUID.randomUUID().toString();

        boolean hostOnly = "REVEAL_NEXT".equals(action) || "ADVANCE_PHASE".equals(action)
                || "CHOOSE_TIE".equals(action) || "AWARD_IMMUNITY".equals(action);
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
            Mono<Void> persist = championships == null ? Mono.empty()
                    : championships.recordAction(rt.roomId, rt.gameSessionId, actionId,
                            UUID.fromString(userId), action, writeJson(data));
            return persist.then(Mono.defer(() -> {
                rt.setState(step.state());
                return afterMutation(rt, step.events());
            }));
        });
    }

    private void triggerElapse(RoomRuntime rt, String expectedPhase, int expectedRound) {
        lock.withLock(rt.roomId, LOCK_TTL, () -> {
            if (rt.state() == null || rt.state().finished() || !expectedPhase.equals(rt.state().phase()) || expectedRound != rt.state().round()) {
                return Mono.empty();
            }
            // A cancel and a firing delay can race; refuse to end a turn that
            // is paused rather than relying on the cancel winning.
            if (rt.paused) {
                return Mono.empty();
            }
            GameRunner runner = new GameRunner(rt.module());
            GameRunner.Step step = runner.elapse(rt.state(), expectedPhase);
            String actionId = UUID.randomUUID().toString();
            Mono<Void> persist = championships == null ? Mono.empty()
                    : championships.recordAction(rt.roomId, rt.gameSessionId, actionId,
                            null, "__ELAPSE", writeJson(Map.of("phase", expectedPhase)));
            return persist.then(Mono.defer(() -> {
                rt.setState(step.state());
                return afterMutation(rt, step.events());
            }));
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
        broadcastPrivateState(rt);
        broadcastSpectatorState(rt);
        pushTurnReminders(rt);
        Mono<Void> finish = rt.state().finished() ? finishGame(rt) : Mono.empty();
        Mono<Void> clock = rt.tournament ? persistTournamentClock(rt.roomId) : Mono.empty();
        return appendAndBroadcast.then(clock).then(finish);
    }

    /**
     * Pushes an OS notification to whichever player(s) newly need to act but
     * aren't actively connected to this room's socket — skips anyone
     * {@code rt.connectedUserIds} already has (they're staring at the
     * board), and only pushes to players added to the waiting set since the
     * last check, not the whole set every time. That distinction matters for
     * a multi-actor phase like TrueArena's Vote: each vote cast shrinks
     * {@code playersToAct} without emptying it, and re-pushing the whole
     * remaining set on every single vote would spam everyone still waiting.
     * Deliberately checks room-socket presence here, not
     * {@link app.truearena.api.inbox.InboxRegistry} — someone could have the
     * app open on the Chats tab, not watching this board, and should still
     * get the reminder.
     */
    private void pushTurnReminders(RoomRuntime rt) {
        if (push == null || !rt.started()) return;
        Set<String> toAct = rt.module().playersToAct(rt.state());
        if (toAct.equals(rt.lastNotifiedTurnFor)) return;
        Set<String> newlyWaiting = new java.util.HashSet<>(toAct);
        newlyWaiting.removeAll(rt.lastNotifiedTurnFor);
        rt.lastNotifiedTurnFor = toAct;
        pushToWhoeverIsOffline(rt, newlyWaiting);
    }

    private void pushToWhoeverIsOffline(RoomRuntime rt, Set<String> candidates) {
        if (push == null || candidates.isEmpty()) return;
        Set<UUID> offline = candidates.stream()
                .filter(id -> !rt.connectedUserIds.contains(id))
                .map(UUID::fromString)
                .collect(java.util.stream.Collectors.toSet());
        if (!offline.isEmpty()) {
            push.sendToUsers(offline, "Your turn", "It's your turn in " + rt.module().gameType(),
                    Map.of("type", "YOUR_TURN", "roomId", rt.roomId.toString(), "gameType", rt.module().gameType()));
        }
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

    /** Stops the phase clock, banking whatever was left on it. */
    private void freezeTimer(RoomRuntime rt) {
        long left = rt.timerDeadlineMs - System.currentTimeMillis();
        rt.timerRemainingMs = Math.max(0, left);
        rt.cancelTimer();
        // cancelTimer() clears timerForPhase, but a pause isn't a phase
        // change — put it back so the resume re-arms the same phase.
        rt.timerForPhase = rt.state() == null ? null : rt.state().phase();
    }

    /** Re-arms the phase clock for exactly the time that was left when it froze. */
    private void thawTimer(RoomRuntime rt) {
        long remaining = rt.timerRemainingMs;
        rt.timerRemainingMs = 0;
        if (remaining <= 0 || rt.state() == null || rt.state().finished()) {
            return;
        }
        String phase = rt.state().phase();
        rt.timerForPhase = phase;
        rt.timerForRound = rt.state().round();
        rt.timerDeadlineMs = System.currentTimeMillis() + remaining;
        int round = rt.state().round();
        rt.timer = Mono.delay(Duration.ofMillis(remaining)).subscribe(x -> triggerElapse(rt, phase, round));
    }

    /** Whole seconds left on the clock — frozen value while paused, live countdown otherwise. */
    private int secondsLeft(RoomRuntime rt) {
        long ms = rt.paused ? rt.timerRemainingMs : rt.timerDeadlineMs - System.currentTimeMillis();
        return (int) Math.max(0, Math.round(ms / 1000.0));
    }

    private void rescheduleTimer(RoomRuntime rt) {
        String phase = rt.state().phase();
        // Word Bluff's describer needs the full turn after a category is
        // chosen. Waiting in the lobby or looking at an unspun wheel must
        // not consume the 60-second describing clock.
        if ("wordbluff".equals(rt.module().gameType()) && "Turn".equals(phase)
                && !Boolean.TRUE.equals(rt.module().broadcastState(rt.state()).data().get("clockStarted"))) {
            rt.cancelTimer();
            return;
        }
        if (phase.equals(rt.timerForPhase) && rt.state().round() == rt.timerForRound) {
            return;
        }
        rt.cancelTimer();
        rt.timerForPhase = phase;
        rt.timerForRound = rt.state().round();
        if (rt.config == null) {
            return;
        }
        Phase definition = rt.module().definePhases(rt.config).stream()
                .filter(p -> p.name().equals(phase))
                .findFirst()
                .orElse(null);
        int secs = definition == null ? 0 : definition.timerSeconds();
        // A phase that starts paused suspends the room the moment it's
        // entered — the clock below is banked rather than started, and only
        // a player resuming releases it. See Phase.awaitingResume.
        if (definition != null && definition.startsPaused() && !rt.paused && !rt.tournament) {
            rt.paused = true;
            rt.bus.tryEmitNext(new LobbyBroadcast("GAME_PAUSED",
                    Map.of("reason", "grace", "phase", phase, "secondsLeft", secs)));
        }
        if (secs > 0) {
            if (rt.paused) {
                // Phase changed while paused (e.g. a forced advance): bank the
                // full duration rather than starting a clock nobody can see.
                rt.timerRemainingMs = secs * 1000L;
                rt.timerDeadlineMs = 0;
                return;
            }
            rt.timerDeadlineMs = System.currentTimeMillis() + secs * 1000L;
            int round = rt.state().round();
            rt.timer = Mono.delay(Duration.ofSeconds(secs)).subscribe(x -> triggerElapse(rt, phase, round));
        } else {
            rt.timerDeadlineMs = 0;
        }
    }

    private void broadcastPhase(RoomRuntime rt) {
        rt.bus.tryEmitNext(new PhaseChanged(rt.state().phase(), rt.state().round()));
    }

    private Mono<Void> finishGame(RoomRuntime rt) {
        var win = rt.module().checkWinCondition(rt.state()).orElse(null);
        Mono<Void> saveResult = win == null ? Mono.empty()
                : (rt.tournament ? resultRows.findByGameSessionId(rt.gameSessionId).hasElement()
                        .flatMap(exists -> exists ? Mono.empty()
                                : resultRows.save(GameResultRow.of(rt.gameSessionId, win.winningSide(),
                                        writeJson(win.perPlayerOutcome()))).then())
                        : resultRows.save(GameResultRow.of(rt.gameSessionId, win.winningSide(),
                                writeJson(win.perPlayerOutcome()))).then());
        Flux<GameEvent> gameEvents = rt.tournament ? Flux.fromIterable(rt.state().events())
                : eventLog.replayAfter(rt.roomId, 0)
                    .flatMap(json -> Mono.fromCallable(() -> mapper.readValue(json, GameEvent.class)));
        Mono<Void> flushEvents = gameEvents
                .concatMap(ge -> (rt.tournament ? eventRows.findByGameSessionIdAndSeq(rt.gameSessionId, ge.seq()).hasElement()
                        : Mono.just(false)).flatMap(exists -> exists ? Mono.empty()
                        : eventRows.save(GameEventRow.of(rt.gameSessionId, ge.seq(), ge.type(),
                                writeJson(ge.payload()), ge.visibility().scope(), ge.visibility().key())).then()))
                .then();
        Mono<Void> endSession = sessions.findById(rt.gameSessionId)
                .flatMap(s -> sessions.save(new GameSessionRow(s.id(), s.roomId(), s.gameType(), s.config(), s.configPresetId(),
                        s.catalogVersion(), s.rngSeed(), rt.state().phase(), rt.state().round(), null, s.startedAt(), Instant.now())))
                .then();
        Mono<Void> endRoom = updateRoomStatus(rt.roomId, "ended");
        Mono<Void> stats = win == null ? Mono.empty() : updateStats(rt, win.perPlayerOutcome());
        Mono<Void> coinRewards = win == null ? Mono.empty() : awardCoins(rt, win.perPlayerOutcome());
        Mono<Void> stakePayout = win == null ? Mono.empty()
                : rooms.findById(rt.roomId).flatMap(room -> payoutStake(room, win.perPlayerOutcome())).then();
        Mono<Void> tournament = championships == null || win == null ? Mono.empty()
                : championships.gameFinished(rt.roomId, rt.gameSessionId, win.perPlayerOutcome());
        Mono<Void> competitive = win == null ? Mono.empty() : recordCompetitive(rt, win);
        return saveResult.then(flushEvents).then(endSession).then(endRoom).then(stats).then(coinRewards)
                .then(stakePayout).then(tournament).then(competitive).then(releaseAgents(rt.roomId));
    }

    /**
     * Match history + rating, for every game type — the competitive system is
     * game-agnostic and decides for itself whether this game counts (see
     * {@code RatedMatchPolicy}). Runs after the tournament step so the
     * championship link exists, and is best-effort like stats and coins: a
     * rating failure must never undo a result, a payout, or an advancement.
     */
    private Mono<Void> recordCompetitive(RoomRuntime rt, app.truearena.engine.WinResult win) {
        if (ratings == null) {
            return Mono.empty();
        }
        return ratings.recordMatch(new app.truearena.api.competitive.RatingService.FinishedGame(
                        rt.gameSessionId, rt.roomId, rt.module().gameType(), win.winningSide(),
                        win.perPlayerOutcome(), Set.copyOf(rt.connectedUserIds)))
                .onErrorResume(e -> {
                    log.warn("competitive record failed for session {}: {}", rt.gameSessionId, e.toString());
                    return Mono.empty();
                });
    }

    /**
     * Stop this room's agent sockets and release its pool memberships. Other
     * rooms using the same system identities are deliberately unaffected.
     */
    private Mono<Void> releaseAgents(UUID roomId) {
        return members.findByRoomId(roomId)
                .concatMap(member -> users.findById(member.userId())
                        .filter(UserRow::isBot)
                        .flatMap(agent -> {
                            if (botRuntimes != null) botRuntimes.stop(roomId, agent.id());
                            return members.deleteByRoomIdAndUserId(roomId, agent.id());
                        }))
                .then();
    }

    /**
     * The staked pot (stake × player count) splits evenly among winners —
     * "won" and "tied" both count as a winner here (a module reports "tied"
     * for a genuine joint win, e.g. Goosi's shared high score or an agreed
     * Draughts draw). A no-op
     * for an unstaked room ({@code stakeCoins == 0}), and never blocks or
     * undoes the participation-coin rewards above if it fails.
     */
    private Mono<Void> payoutStake(RoomRow room, Map<String, String> perPlayerOutcome) {
        if (room.stakeCoins() <= 0) {
            return Mono.empty();
        }
        List<String> winners = perPlayerOutcome.entrySet().stream()
                .filter(e -> "won".equals(e.getValue()) || "tied".equals(e.getValue()))
                .map(Map.Entry::getKey)
                .toList();
        if (winners.isEmpty()) {
            return Mono.empty();
        }
        long pot = room.stakeCoins() * perPlayerOutcome.size();
        long share = pot / winners.size();
        long remainder = pot - share * winners.size(); // integer-division leftover — first winner gets the odd coin, nothing is lost
        return Flux.fromIterable(winners)
                .index()
                .flatMap(t -> {
                    UUID userId;
                    try {
                        userId = UUID.fromString(t.getT2());
                    } catch (IllegalArgumentException ex) {
                        return Mono.empty();
                    }
                    long amount = share + (t.getT1() == 0 ? remainder : 0);
                    if (amount <= 0) {
                        return Mono.empty();
                    }
                    return coins.credit(userId, amount, CoinService.REASON_MATCH_STAKE_PAYOUT, room.id())
                            .onErrorResume(err -> {
                                log.warn("stake payout failed for user {} in room {}: {}", userId, room.id(), err.toString());
                                return Mono.empty();
                            });
                })
                .then();
    }

    /**
     * A flat participation/result reward, generic across every game type —
     * built straight off {@code WinResult.perPlayerOutcome()} (every module
     * produces this the same shape) rather than {@code roleRows}, which is
     * TrueArena-specific and empty for Draughts/Word Bluff/Goosi. Best-
     * effort per player: one payout failing (e.g. a bot's row, or any
     * transient error) never undoes the result/session writes above, and
     * never blocks the others.
     */
    /**
     * Pays out at the end of a match — but only a match against another
     * person. Cyber Agents are a free, always-available shared pool (see
     * {@code BotService}), so a match against one pays nothing at all, win
     * or lose: any positive payout there would make grinding the nearest
     * free agent a zero-cost, zero-risk way to mint coins. See the class
     * doc on {@link CoinService}. Agents themselves are never paid either —
     * they have nothing to spend it on, and a bot's balance would only
     * muddy the ledger.
     *
     * <p>Each player is told what they earned (zero, against an agent) so
     * the results screen can show it, rather than the number quietly
     * changing — or conspicuously not changing — in their wallet.
     */
    private Mono<Void> awardCoins(RoomRuntime rt, Map<String, String> perPlayerOutcome) {
        List<UUID> ids = perPlayerOutcome.keySet().stream()
                .map(GameOrchestrator::parseUuid)
                .filter(Objects::nonNull)
                .toList();
        if (ids.isEmpty()) {
            return Mono.empty();
        }
        return Flux.fromIterable(ids)
                .concatMap(users::findById)
                .collectList()
                .flatMapMany(rows -> {
                    boolean vsAgent = rows.stream().anyMatch(UserRow::isBot);
                    return Flux.fromIterable(rows)
                            .filter(u -> !u.isBot())
                            .concatMap(u -> {
                                if (vsAgent) {
                                    rt.tellUser(u.id().toString(), Envelope.of(MessageType.EVENT, Map.of(
                                            "type", "COINS_AWARDED",
                                            "data", Map.of("amount", 0L, "vsAgent", true))));
                                    return Mono.<Void>empty();
                                }
                                String outcome = perPlayerOutcome.getOrDefault(u.id().toString(), "lost");
                                long amount = switch (outcome) {
                                    case "won" -> CoinService.WIN_VS_PERSON;
                                    case "tied" -> CoinService.TIE_VS_PERSON;
                                    default -> CoinService.LOSS_VS_PERSON;
                                };
                                String reason = switch (outcome) {
                                    case "won" -> CoinService.REASON_MATCH_WIN;
                                    case "tied" -> CoinService.REASON_MATCH_TIE;
                                    default -> CoinService.REASON_MATCH_LOSS;
                                };
                                return coins.credit(u.id(), amount, reason, null)
                                        .doOnSuccess(balance -> rt.tellUser(u.id().toString(),
                                                Envelope.of(MessageType.EVENT, Map.of(
                                                        "type", "COINS_AWARDED",
                                                        "data", Map.of("amount", amount, "vsAgent", false)))))
                                        .onErrorResume(err -> {
                                            log.warn("coin reward failed for user {}: {}", u.id(), err.toString());
                                            return Mono.empty();
                                        });
                            });
                })
                .then();
    }

    private static UUID parseUuid(String raw) {
        try {
            return UUID.fromString(raw);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    /**
     * Folds this game's outcome into each player's lifetime rollup (group_id IS NULL —
     * ad-hoc games only touch that row, per docs/DATABASE.md). Best-effort: a stats
     * write failing doesn't undo the result/session writes above.
     */
    private Mono<Void> updateStats(RoomRuntime rt, Map<String, String> perPlayerOutcome) {
        return roleRows.findByGameSessionId(rt.gameSessionId)
                .concatMap(role -> {
                    boolean won = "won".equals(perPlayerOutcome.get(role.userId().toString()));
                    boolean wasTraitor = "traitor".equals(role.roleType()) || "recruited_traitor".equals(role.roleType());
                    return statsRows.findByUserIdAndGroupIdIsNull(role.userId())
                            .defaultIfEmpty(PlayerStatsRow.lifetimeZero(role.userId()))
                            .flatMap(row -> statsRows.save(row.plusGame(won, wasTraitor)));
                })
                .then()
                .onErrorResume(e -> {
                    log.warn("stats update failed for session {}: {}", rt.gameSessionId, e.toString());
                    return Mono.empty();
                });
    }

    private Mono<Void> updateRoomStatus(UUID roomId, String status) {
        return rooms.findById(roomId)
                .flatMap(r -> rooms.save(r.withStatus(status)))
                .then();
    }

    // ---------------------------------------------------------------- visibility + wire helpers

    private boolean visibleTo(RoomRuntime rt, GameEvent ge, String userId) {
        var v = ge.visibility();
        if (v.isPublic()) {
            return true;
        }
        if (rt.spectatorUserIds.contains(userId)) return false;
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
        return toEnvelope(rt, msg, userId, rt.spectatorUserIds.contains(userId));
    }

    Mono<Envelope> toEnvelope(RoomRuntime rt, Object msg, String userId, boolean spectator) {
        // Use the connection's authenticated mode, even when this account also
        // has a player connection or another socket has just disconnected.
        if (spectator) {
            if (msg instanceof GameEvent event && !event.visibility().isPublic()) return Mono.empty();
            if (msg instanceof ChatMessage chat && ChatMessage.TRAITORS.equals(chat.channel())) return Mono.empty();
            if (msg instanceof Envelope env && env.type() == MessageType.SNAPSHOT && rt.started()) {
                return Mono.just(Envelope.of(MessageType.SNAPSHOT, snapshotView(rt, userId, true)));
            }
        }
        if (msg instanceof GameEvent ge) {
            return visibleTo(rt, ge, userId) ? Mono.just(eventEnvelope(ge)) : Mono.empty();
        }
        if (msg instanceof LobbyBroadcast lb) {
            return Mono.just(Envelope.of(MessageType.EVENT, Map.of("type", lb.type(), "data", lb.data())));
        }
        if (msg instanceof PhaseChanged pc) {
            return Mono.just(Envelope.of(MessageType.PHASE, Map.of("phase", pc.phase(), "round", pc.round())));
        }
        if (msg instanceof ChatMessage cm) {
            if (ChatMessage.TRAITORS.equals(cm.channel()) && (rt.spectatorUserIds.contains(userId) || !roleGroupMatches("traitor", String.valueOf(rt.roleByUser().get(userId))))) {
                return Mono.empty(); // the same visibility guarantee GameEvent role-scoping gets, applied to chat
            }
            return Mono.just(Envelope.of(MessageType.EVENT, Map.of("type", "CHAT_MESSAGE",
                    "data", Map.of("channel", cm.channel(), "from", cm.fromUserId(), "text", cm.text(), "ts", cm.ts()))));
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
