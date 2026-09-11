package app.truearena.room;

import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.UUID;
import java.util.function.Supplier;

/**
 * The single-writer lock around one room's state transitions (Architecture §2.2).
 * {@code SET NX PX} + a short poll-retry; correct across pods, and also serializes
 * concurrent WS frames for the same room within one pod.
 */
@Component
public class RoomLock {

    private static final Duration POLL = Duration.ofMillis(25);
    private static final Duration ACQUIRE_TIMEOUT = Duration.ofSeconds(5);

    private final ReactiveStringRedisTemplate redis;

    public RoomLock(ReactiveStringRedisTemplate redis) {
        this.redis = redis;
    }

    public <T> Mono<T> withLock(UUID roomId, Duration ttl, Supplier<Mono<T>> action) {
        String key = "lock:room:" + roomId;
        return acquire(key, ttl)
                .then(Mono.defer(action))
                .flatMap(result -> release(key).thenReturn(result))
                // action is often a Mono<Void>, which completes with no onNext at all —
                // flatMap above never fires then, so release still has to happen here.
                .switchIfEmpty(Mono.defer(() -> release(key).then(Mono.empty())))
                .onErrorResume(e -> release(key).then(Mono.error(e)));
    }

    private Mono<Boolean> acquire(String key, Duration ttl) {
        return redis.opsForValue().setIfAbsent(key, "1", ttl)
                .flatMap(ok -> Boolean.TRUE.equals(ok)
                        ? Mono.just(true)
                        : Mono.delay(POLL).then(Mono.defer(() -> acquire(key, ttl))))
                .timeout(ACQUIRE_TIMEOUT);
    }

    private Mono<Void> release(String key) {
        return redis.delete(key).then();
    }
}
