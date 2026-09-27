package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.reactive.socket.WebSocketMessage;
import org.springframework.web.reactive.socket.WebSocketSession;
import org.springframework.web.reactive.socket.client.ReactorNettyWebSocketClient;
import org.springframework.web.reactive.socket.client.WebSocketClient;
import reactor.core.Disposable;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

import java.net.URI;
import java.time.Duration;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ThreadLocalRandom;

/**
 * One bot's live connection — opens `/ws/room/{id}` exactly like the Flutter
 * app does (same envelope contract, same actions), and knows nothing about
 * any game's rules; every decision is delegated to a {@link GameBotAdapter}.
 * This is what "generic" means in practice: adding a new game to the bot
 * roster is writing an adapter, never touching this class.
 *
 * <p>v1 simplification, documented rather than silent: a dropped connection
 * just stops the bot (no auto-reconnect) — same spirit as the WS transport's
 * other Phase 4 simplifications in docs/DEV_REFERENCE.md.
 */
public final class BotRuntime {

    private static final Logger log = LoggerFactory.getLogger(BotRuntime.class);
    private static final TypeReference<Map<String, Object>> MAP_TYPE = new TypeReference<>() {
    };

    private final WebSocketClient client = new ReactorNettyWebSocketClient();
    private final ObjectMapper mapper;
    private final URI uri;
    private final GameBotAdapter adapter;
    private final LlmMovePicker picker;
    private final String botUserId;
    private final Difficulty difficulty;
    private final String botName;
    private final String gameName;
    private final AgentBanter banter = new AgentBanter();

    private volatile Disposable subscription;
    private volatile boolean actionPending;
    /** Set when a capture lands, so the next own-move line knows it wasn't routine. */
    private volatile boolean lastMoveWasNotable;

    public BotRuntime(ObjectMapper mapper, URI uri, GameBotAdapter adapter, LlmMovePicker picker,
                       String botUserId, Difficulty difficulty, String botName, String gameName) {
        this.botName = botName;
        this.gameName = gameName;
        this.mapper = mapper;
        this.uri = uri;
        this.adapter = adapter;
        this.picker = picker;
        this.botUserId = botUserId;
        this.difficulty = difficulty;
    }

    public void start() {
        subscription = client.execute(uri, this::handle)
                .subscribe(
                        v -> { },
                        err -> log.warn("bot {} disconnected: {}", botUserId, err.toString()));
    }

    public void stop() {
        Disposable s = subscription;
        if (s != null) {
            s.dispose();
        }
    }

    private Mono<Void> handle(WebSocketSession session) {
        Sinks.Many<String> outbound = Sinks.many().unicast().onBackpressureBuffer();
        emit(outbound, "HELLO", Map.of("lastSeq", 0));
        emit(outbound, "READY_SET", Map.of("ready", true));

        Mono<Void> inbound = session.receive()
                .map(WebSocketMessage::getPayloadAsText)
                .concatMap(text -> onFrame(text, outbound))
                .then();
        Mono<Void> outboundDone = session.send(outbound.asFlux().map(session::textMessage));
        return Mono.when(inbound, outboundDone);
    }

    @SuppressWarnings("unchecked")
    private Mono<Void> onFrame(String text, Sinks.Many<String> outbound) {
        return Mono.fromCallable(() -> mapper.readValue(text, MAP_TYPE))
                .flatMap(envelope -> {
                    String type = String.valueOf(envelope.get("type"));
                    Map<String, Object> payload = (Map<String, Object>) envelope.getOrDefault("payload", Map.of());

                    if ("ERROR".equals(type) && actionPending) {
                        // the model (or its fallback) proposed something the
                        // server rejected — try the fallback once so the game
                        // never stalls on this bot's turn.
                        actionPending = false;
                        adapter.fallbackAction(botUserId).ifPresent(a -> sendAction(outbound, a));
                        return Mono.empty();
                    }

                    Mono<Void> reaction = reactTo(type, payload, outbound);

                    Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(type, payload, botUserId, difficulty);
                    if (prompt.isEmpty()) {
                        return reaction;
                    }
                    GameBotAdapter.BotPrompt p = prompt.get();
                    if (p.speak()) {
                        return describeAloud(p, outbound).then(reaction);
                    }
                    actionPending = true;
                    return picker.pickMove(p.systemPrompt(), p.userPrompt(), difficulty)
                            .flatMap(raw -> {
                                PlayerAction action = adapter.parseAction(raw, botUserId)
                                        .or(() -> adapter.fallbackAction(botUserId))
                                        .orElse(null);
                                if (action == null) {
                                    actionPending = false;
                                    return Mono.empty();
                                }
                                // A real opponent doesn't move the instant it's their turn —
                                // pause as if "thinking" before committing, so the bot feels
                                // present rather than mechanical. Purely cosmetic: the move
                                // itself was already decided above.
                                return Mono.delay(thinkingDelay(difficulty))
                                        .doOnNext(t -> sendAction(outbound, action))
                                        .then(maybeSay(outbound, describeOwnMove(action)));
                            });
                })
                .onErrorResume(e -> {
                    log.warn("bot {} could not process a frame: {}", botUserId, e.toString());
                    return Mono.empty(); // one bad frame shouldn't kill the whole session
                });
    }

    /**
     * Table talk about something that just happened. Fire-and-forget by
     * design: a failed or unusable line means the agent simply says nothing,
     * which must never delay or block its actual move.
     */
    /** How long the table gets with a clue before the agent moves on. */
    private static final Duration CLUE_DWELL = Duration.ofSeconds(11);

    /**
     * The agent's turn as describer: it says a clue out loud, gives the
     * table a moment with it, then moves to the next word.
     *
     * <p>The follow-on is scheduled whatever the model returns — a refused
     * or empty clue must not leave the agent sitting on a word for the rest
     * of the turn, which is exactly how its turns used to pass in silence.
     */
    private Mono<Void> describeAloud(GameBotAdapter.BotPrompt p, Sinks.Many<String> outbound) {
        return picker.pickMove(p.systemPrompt(), p.userPrompt(), difficulty)
                .map(raw -> cleanClue(raw, p.forbidden()))
                .onErrorReturn("")
                .defaultIfEmpty("")
                .flatMap(line -> {
                    if (!line.isBlank()) {
                        log.debug("clue bot={} says '{}'", botUserId, line);
                        emit(outbound, "CHAT_SEND", Map.of("channel", "agent", "text", line));
                    }
                    return Mono.delay(CLUE_DWELL)
                            .doOnNext(x -> adapter.fallbackAction(botUserId)
                                    .ifPresent(a -> sendAction(outbound, a)))
                            .then();
                });
    }

    /**
     * Tidies a clue, and drops it outright if the model said the word it was
     * describing — saying it would hand the round away, and that's not
     * something to leave to the model's good behaviour.
     */
    private static String cleanClue(String raw, String forbidden) {
        if (raw == null) {
            return "";
        }
        String line = raw.trim()
                .replaceAll("^[\"\'`]+|[\"\'`]+$", "")
                .replaceAll("\\s+", " ")
                .trim();
        if (line.length() > 180) {
            line = line.substring(0, 180);
        }
        if (forbidden != null && !forbidden.isBlank()
                && line.toLowerCase(Locale.ROOT).contains(forbidden.toLowerCase(Locale.ROOT))) {
            return "";
        }
        return line;
    }

    private Mono<Void> maybeSay(Sinks.Many<String> outbound, String situation) {
        if (situation == null) {
            return Mono.empty();
        }
        boolean notable = situation.contains("captur") || situation.contains("ended")
                || situation.contains("won") || situation.contains("lost");
        boolean speaking = banter.shouldSpeak(notable);
        log.debug("banter bot={} situation='{}' speaking={}", botUserId, situation, speaking);
        if (!speaking) {
            return Mono.empty();
        }
        return picker.pickMove(banter.systemPrompt(botName, gameName, difficulty),
                        banter.userPrompt(situation), difficulty)
                .mapNotNull(banter::accept)
                // A beat after the move, so it reads as a reaction rather
                // than something said simultaneously with playing.
                .delayElement(Duration.ofMillis(ThreadLocalRandom.current().nextInt(600, 1500)))
                .doOnNext(line -> {
                    log.debug("banter bot={} says '{}'", botUserId, line);
                    emit(outbound, "CHAT_SEND", Map.of("channel", "agent", "text", line));
                })
                .onErrorResume(e -> {
                    log.debug("bot {} had nothing to say: {}", botUserId, e.toString());
                    return Mono.empty();
                })
                .then();
    }

    /** Turns an inbound event into a one-line description worth reacting to, or null. */
    @SuppressWarnings("unchecked")
    private Mono<Void> reactTo(String type, Map<String, Object> payload, Sinks.Many<String> outbound) {
        if (!"EVENT".equals(type)) {
            return Mono.empty();
        }
        String eventType = String.valueOf(payload.get("type"));
        Map<String, Object> data = (Map<String, Object>) payload.getOrDefault("data", Map.of());
        Object by = data.get("by");
        boolean mine = botUserId.equals(String.valueOf(by));

        String situation = switch (eventType) {
            case "PIECE_CAPTURED", "CAPTURED" -> {
                if (mine) {
                    // Remember it so the line after our move can mention it;
                    // commenting here as well would double up on one event.
                    lastMoveWasNotable = true;
                    yield null;
                }
                yield "the human just captured one of your pieces";
            }
            // A plain move is not worth remarking on. Leaving this silent is
            // the point: it's what makes the occasional line feel earned.
            case "PIECE_MOVED", "SOWN" -> null;
            case "GAME_OVER" -> "the game just ended";
            default -> null;
        };
        return maybeSay(outbound, situation);
    }

    /** What we just did, in plain words — never notation, which the model would parrot. */
    private String describeOwnMove(PlayerAction action) {
        boolean notable = lastMoveWasNotable;
        lastMoveWasNotable = false;
        return switch (action.type()) {
            case "MOVE" -> notable ? "you just captured one of the human's pieces" : "you just made your move";
            case "SOW" -> "you just sowed one of your pits";
            case "SKIP" -> "you gave up on the current word";
            case "FORFEIT" -> null; // quitting doesn't need a quip
            default -> "you just took your turn";
        };
    }

    /** A believable-but-bounded "thinking" pause, longer for harder bots. */
    private static Duration thinkingDelay(Difficulty difficulty) {
        int minMs = switch (difficulty) {
            case EASY -> 500;
            case MEDIUM -> 900;
            case HARD -> 1400;
        };
        int maxMs = switch (difficulty) {
            case EASY -> 1100;
            case MEDIUM -> 1800;
            case HARD -> 2600;
        };
        return Duration.ofMillis(ThreadLocalRandom.current().nextInt(minMs, maxMs + 1));
    }

    private void sendAction(Sinks.Many<String> outbound, PlayerAction action) {
        actionPending = false;
        emit(outbound, "PLAYER_ACTION", Map.of("action", action.type(), "data", action.data(), "actionId", action.actionId()));
    }

    private void emit(Sinks.Many<String> outbound, String type, Map<String, Object> payload) {
        try {
            String json = mapper.writeValueAsString(Map.of(
                    "v", 1, "type", type, "ts", System.currentTimeMillis(), "payload", payload));
            outbound.tryEmitNext(json);
        } catch (Exception e) {
            log.warn("bot {} failed to encode a {} frame: {}", botUserId, type, e.toString());
        }
    }
}
