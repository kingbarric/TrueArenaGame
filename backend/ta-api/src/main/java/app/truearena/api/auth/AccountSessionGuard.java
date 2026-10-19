package app.truearena.api.auth;

import app.truearena.persistence.UserRepository;
import app.truearena.api.safety.AgeSafetyService;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.socket.CloseStatus;
import org.springframework.web.reactive.socket.WebSocketSession;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/** A valid signature is insufficient once the account has been deleted. */
@Component
public class AccountSessionGuard {
    private final UserRepository users;
    private final AgeSafetyService ages;
    private final ConcurrentHashMap<UUID, Set<WebSocketSession>> sockets = new ConcurrentHashMap<>();

    public AccountSessionGuard(UserRepository users, AgeSafetyService ages) { this.users = users; this.ages=ages; }

    public Mono<Boolean> exists(UUID user) {
        return users.findById(user).map(row -> !row.isBot()).defaultIfEmpty(false);
    }

    public Mono<Void> require(UUID user) {
        return exists(user).flatMap(found -> found ? Mono.empty()
                : Mono.error(new SecurityException("account unavailable"))).then(ages.requireAccess(user));
    }

    /** Only after room JWT and membership authentication: Cyber Agents are
     * valid game participants, while normal HTTP/inbox access still rejects bots. */
    public Mono<Void> requireRoomParticipant(UUID user) {
        return users.findById(user).switchIfEmpty(Mono.error(new SecurityException("account unavailable")))
                .flatMap(row -> row.isBot()?Mono.empty():ages.requireAccess(user));
    }

    public void register(UUID user, WebSocketSession socket) {
        sockets.computeIfAbsent(user, ignored -> ConcurrentHashMap.newKeySet()).add(socket);
    }

    public void remove(UUID user, WebSocketSession socket) {
        sockets.computeIfPresent(user, (id, sessions) -> {
            sessions.remove(socket);
            return sessions.isEmpty() ? null : sessions;
        });
    }

    public Mono<Void> close(UUID user) {
        return Mono.defer(() -> {
            Set<WebSocketSession> sessions = sockets.remove(user);
            return sessions == null ? Mono.empty() : Flux.fromIterable(sessions)
                    .flatMap(s -> s.close(new CloseStatus(4401, "account deleted"))
                            .onErrorResume(error -> Mono.empty())).then();
        });
    }
}
