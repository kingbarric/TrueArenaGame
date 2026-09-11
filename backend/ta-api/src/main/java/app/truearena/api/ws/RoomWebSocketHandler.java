package app.truearena.api.ws;

import app.truearena.room.RoomRuntime;
import app.truearena.ws.contract.Envelope;
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

/**
 * {@code /ws/room/{roomId}?token=<accessJwt>}. One frame format both directions —
 * {@link Envelope} — everything else is {@link GameOrchestrator}.
 */
@Component
public class RoomWebSocketHandler implements WebSocketHandler {

    private static final Logger log = LoggerFactory.getLogger(RoomWebSocketHandler.class);
    private static final CloseStatus UNAUTHORIZED = new CloseStatus(4401, "unauthorized");

    private final GameOrchestrator orchestrator;
    private final ObjectMapper mapper;

    public RoomWebSocketHandler(GameOrchestrator orchestrator, ObjectMapper mapper) {
        this.orchestrator = orchestrator;
        this.mapper = mapper;
    }

    @Override
    public Mono<Void> handle(WebSocketSession session) {
        String path = session.getHandshakeInfo().getUri().getPath();
        String[] segments = path.split("/");
        String roomIdRaw = segments[segments.length - 1];
        String token = UriComponentsBuilder.fromUri(session.getHandshakeInfo().getUri())
                .build().getQueryParams().getFirst("token");

        return orchestrator.authenticate(roomIdRaw, token == null ? "" : token)
                .flatMap(auth -> runSession(session, auth))
                .onErrorResume(e -> {
                    log.debug("WS handshake rejected for {}: {}", path, e.toString());
                    return session.close(UNAUTHORIZED);
                });
    }

    private Mono<Void> runSession(WebSocketSession session, GameOrchestrator.Authed auth) {
        return orchestrator.ensureRuntime(auth.roomId()).flatMap(rt -> {
            Sinks.Many<Object> personal = Sinks.many().unicast().onBackpressureBuffer();
            rt.unicast.put(auth.userId(), personal);

            Flux<WebSocketMessage> outbound = Flux.merge(
                            rt.bus.asFlux().flatMap(msg -> orchestrator.toEnvelope(rt, msg, auth.userId())),
                            personal.asFlux().flatMap(msg -> orchestrator.toEnvelope(rt, msg, auth.userId())))
                    .map(env -> session.textMessage(writeJson(env)));

            Mono<Void> inbound = session.receive()
                    .map(WebSocketMessage::getPayloadAsText)
                    .concatMap(text -> orchestrator.handleFrame(rt, auth.userId(), text)
                            .onErrorResume(e -> {
                                log.warn("unhandled error processing frame for room {} user {}: {}",
                                        auth.roomId(), auth.userId(), e.toString());
                                return Mono.empty();
                            }))
                    .then();

            return orchestrator.onConnect(rt, auth.userId())
                    .then(session.send(outbound).and(inbound))
                    .doFinally(sig -> orchestrator.onDisconnect(rt, auth.userId()).subscribe());
        });
    }

    private String writeJson(Envelope env) {
        try {
            return mapper.writeValueAsString(env);
        } catch (Exception e) {
            throw new IllegalStateException("cannot serialize envelope", e);
        }
    }
}
