package app.truearena.api.auth;

import app.truearena.persistence.UserRepository;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.security.SecureRandom;

/** Picks a random, available handle for a signup that didn't choose one. */
@Component
public class UsernameGenerator {

    private static final SecureRandom RNG = new SecureRandom();
    private static final String[] ADJECTIVES = {
            "quiet", "quick", "sly", "brave", "lucky", "clever", "loyal", "sneaky", "bold", "calm"
    };
    private static final String[] NOUNS = {
            "fox", "owl", "wolf", "raven", "lynx", "hawk", "otter", "viper", "falcon", "badger"
    };
    private static final int MAX_ATTEMPTS = 8;

    private final UserRepository users;

    public UsernameGenerator(UserRepository users) {
        this.users = users;
    }

    /** {@code requested}, if given and free; otherwise a fresh random handle. */
    public Mono<String> resolve(String requested) {
        if (requested != null && !requested.isBlank()) {
            return users.existsByUsername(requested)
                    .flatMap(taken -> taken
                            ? Mono.error(app.truearena.api.support.ApiExceptions.conflict("username already taken"))
                            : Mono.just(requested));
        }
        return generateUnused(1);
    }

    private Mono<String> generateUnused(int attempt) {
        String candidate = ADJECTIVES[RNG.nextInt(ADJECTIVES.length)] + "_"
                + NOUNS[RNG.nextInt(NOUNS.length)] + RNG.nextInt(10_000);
        return users.existsByUsername(candidate)
                .flatMap(taken -> {
                    if (!taken) {
                        return Mono.just(candidate);
                    }
                    if (attempt >= MAX_ATTEMPTS) {
                        // astronomically unlikely with this pool size, but fall back to
                        // something unique-by-construction rather than loop forever.
                        return Mono.just("player_" + java.util.UUID.randomUUID().toString().substring(0, 8));
                    }
                    return generateUnused(attempt + 1);
                });
    }
}
