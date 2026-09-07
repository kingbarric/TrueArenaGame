package app.truearena.api.support;

import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import reactor.core.publisher.Mono;

import java.util.UUID;

/** Reads the authenticated user id (JWT subject) from the reactive security context. */
public final class CurrentUser {

    private CurrentUser() {
    }

    public static Mono<UUID> id() {
        return ReactiveSecurityContextHolder.getContext()
                .map(ctx -> UUID.fromString((String) ctx.getAuthentication().getPrincipal()));
    }
}
