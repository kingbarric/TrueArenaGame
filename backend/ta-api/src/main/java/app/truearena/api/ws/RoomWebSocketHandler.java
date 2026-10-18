package app.truearena.api.ws;

import app.truearena.room.RoomRuntime;
import app.truearena.api.auth.AccountSessionGuard;
import java.util.UUID;
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
    private final AccountSessionGuard accounts;

    public RoomWebSocketHandler(GameOrchestrator orchestrator, ObjectMapper mapper, AccountSessionGuard accounts) {
        this.orchestrator = orchestrator;
        this.mapper = mapper;
        this.accounts = accounts;
    }

    @Override
    public Mono<Void> handle(WebSocketSession session) {
        String path = session.getHandshakeInfo().getUri().getPath();
        String[] segments = path.split("/");
        String roomIdRaw = segments[segments.length - 1];
        var query = UriComponentsBuilder.fromUri(session.getHandshakeInfo().getUri()).build().getQueryParams();
        String token = query.getFirst("token");
        boolean spectate = "true".equals(query.getFirst("spectate"));

        return orchestrator.authenticate(roomIdRaw, token == null ? "" : token, spectate)
                .flatMap(auth -> accounts.require(UUID.fromString(auth.userId()))
                        .then(Mono.defer(() -> runSession(session, auth))))
                .onErrorResume(e -> {
                    log.debug("WS handshake rejected for {}: {}", path, e.toString());
                    return session.close(UNAUTHORIZED);
                });
    }

    private Mono<Void> runSession(WebSocketSession session, GameOrchestrator.Authed auth) {
        UUID user = UUID.fromString(auth.userId());
        accounts.register(user, session);
        return orchestrator.ensureRuntime(auth.roomId()).flatMap(rt -> {
            Sinks.Many<Object> personal = Sinks.many().unicast().onBackpressureBuffer();
            synchronized (rt) {
                rt.unicast.put(auth.userId(), personal);
            }

            Flux<WebSocketMessage> outbound = Flux.merge(
                            rt.bus.asFlux().flatMap(msg -> orchestrator.toEnvelope(rt, msg, auth.userId(), auth.spectator())),
                            personal.asFlux().flatMap(msg -> orchestrator.toEnvelope(rt, msg, auth.userId(), auth.spectator())))
                    .map(env -> session.textMessage(writeJson(env)));

            Mono<Void> inbound = session.receive()
                    .map(WebSocketMessage::getPayloadAsText)
                    .concatMap(text -> accounts.require(user)
                            .then(Mono.defer(() -> orchestrator.handleFrame(rt, auth.userId(), text, auth.spectator())))
                            .onErrorResume(e -> {
                                log.warn("unhandled error processing frame for room {} user {}: {}",
                                        auth.roomId(), auth.userId(), e.toString());
                                return Mono.empty();
                            }))
                    .then();

            Mono<Void> connect = auth.spectator() ? orchestrator.onSpectatorConnect(rt, auth.userId()) : orchestrator.onConnect(rt, auth.userId());
            Runnable disconnect = () -> {
                Mono<Void> cleanup;
                synchronized (rt) {
                    if (rt.retired) return;
                    // A new socket may already have replaced this one. The old
                    // socket must not disconnect the player or migrate the host.
                    if (rt.unicast.get(auth.userId()) != personal) return;
                    cleanup = auth.spectator()
                            ? orchestrator.onSpectatorDisconnect(rt, auth.userId())
                            : orchestrator.onDisconnect(rt, auth.userId());
                }
                cleanup.subscribe();
            };

            return connect
                    .then(session.send(outbound).and(inbound))
                    .doFinally(sig -> disconnect.run());
        }).doFinally(signal -> accounts.remove(user, session));
    }

    private String writeJson(Envelope env) {
        try {
            return mapper.writeValueAsString(env);
        } catch (Exception e) {
            throw new IllegalStateException("cannot serialize envelope", e);
        }
    }
}
