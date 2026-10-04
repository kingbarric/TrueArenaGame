package app.truearena.api.inbox;

import app.truearena.api.auth.JwtService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.socket.CloseStatus;
import org.springframework.web.reactive.socket.WebSocketHandler;
import org.springframework.web.reactive.socket.WebSocketMessage;
import org.springframework.web.reactive.socket.WebSocketSession;
import org.springframework.web.util.UriComponentsBuilder;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

import java.util.Map;
import java.util.UUID;

/**
 * {@code /ws/inbox?token=<accessJwt>} — one connection per signed-in user,
 * independent of any game room. Two things ride this channel today:
 *
 * <ul>
 *   <li>Client → server: {@code CALL_JOINED}/{@code CALL_LEFT} frames
 *       ({@code {"roomName": "..."}}), sent by {@code CallScreen} when it
 *       connects to / leaves a LiveKit room — how the server learns who's
 *       currently on a call together.</li>
 *   <li>Client → server: {@code APP_FOREGROUND}/{@code APP_BACKGROUND}
 *       (no payload), sent by {@code AppState} on app lifecycle changes —
 *       the socket itself often survives backgrounding for a while, so this
 *       is how {@code InboxRegistry.isOnline} stays accurate for push
 *       gating even while the socket is still technically connected.</li>
 *   <li>Server → client: {@code GAME_STARTING} frames, pushed to everyone
 *       on a call when one of them creates a room (see
 *       {@code RoomService.create}) — the "someone spun up a game, here's a
 *       Join button" notification.</li>
 * </ul>
 *
 * Same envelope shape as {@code /ws/room/{id}} ({@code {v, type, ts,
 * payload}}) for one less thing for the client to special-case.
 */
@Component
public class InboxWebSocketHandler implements WebSocketHandler {

    private static final Logger log = LoggerFactory.getLogger(InboxWebSocketHandler.class);
    private static final CloseStatus UNAUTHORIZED = new CloseStatus(4401, "unauthorized");

    private final InboxRegistry registry;
    private final JwtService jwt;
    private final ObjectMapper mapper;

    public InboxWebSocketHandler(InboxRegistry registry, JwtService jwt, ObjectMapper mapper) {
        this.registry = registry;
        this.jwt = jwt;
        this.mapper = mapper;
    }

    @Override
    public Mono<Void> handle(WebSocketSession session) {
        String token = UriComponentsBuilder.fromUri(session.getHandshakeInfo().getUri())
                .build().getQueryParams().getFirst("token");
        return Mono.fromCallable(() -> jwt.parseAccess(token == null ? "" : token))
                .onErrorMap(e -> new SecurityException("bad token"))
                .flatMap(userId -> runSession(session, userId))
                .onErrorResume(e -> {
                    log.debug("inbox WS handshake rejected: {}", e.toString());
                    return session.close(UNAUTHORIZED);
                });
    }

    @SuppressWarnings("unchecked")
    private Mono<Void> runSession(WebSocketSession session, UUID userId) {
        Sinks.Many<Object> outbound = Sinks.many().unicast().onBackpressureBuffer();
        registry.connect(userId, outbound);

        Flux<WebSocketMessage> out = outbound.asFlux().map(payload -> session.textMessage(writeJson(payload)));

        Mono<Void> inbound = session.receive()
                .map(WebSocketMessage::getPayloadAsText)
                .concatMap(text -> Mono.fromCallable(() -> (Map<String, Object>) mapper.readValue(text, Map.class))
                        .doOnNext(env -> handleFrame(userId, env))
                        .onErrorResume(e -> {
                            log.debug("inbox frame from {} ignored: {}", userId, e.toString());
                            return Mono.empty();
                        }))
                .then();

        return session.send(out).and(inbound)
                .doFinally(sig -> registry.disconnect(userId, outbound));
    }

    @SuppressWarnings("unchecked")
    private void handleFrame(UUID userId, Map<String, Object> envelope) {
        String type = String.valueOf(envelope.get("type"));
        Map<String, Object> payload = (Map<String, Object>) envelope.getOrDefault("payload", Map.of());
        switch (type) {
            case "CALL_JOINED" -> {
                String roomName = String.valueOf(payload.get("roomName"));
                registry.joinCall(userId, roomName);
            }
            case "CALL_LEFT" -> registry.leaveCall(userId);
            case "APP_FOREGROUND" -> registry.setForeground(userId, true);
            case "APP_BACKGROUND" -> registry.setForeground(userId, false);
            default -> log.debug("inbox: no handler for frame type {}", type);
        }
    }

    private String writeJson(Object payload) {
        try {
            return mapper.writeValueAsString(Map.of(
                    "v", 1, "type", "EVENT", "ts", System.currentTimeMillis(), "payload", payload));
        } catch (Exception e) {
            throw new IllegalStateException("cannot serialize inbox payload", e);
        }
    }
}
