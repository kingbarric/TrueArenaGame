package app.truearena.room;

import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.UUID;

/**
 * The durable per-room event log used for reconnection replay (Architecture §2.2/§4).
 * A Redis LIST, not a Stream: {@code seq} is our own gap-free 1-based counter (the
 * reducer only ever runs under {@link RoomLock}), so list index {@code i} always holds
 * the event with {@code seq == i + 1} — {@code LRANGE key lastSeq -1} is exactly
 * "everything after lastSeq". Callers own JSON encoding; this class only moves strings.
 */
@Component
public class RoomEventLog {

    private static final Duration TTL = Duration.ofHours(6);

    private final ReactiveStringRedisTemplate redis;

    public RoomEventLog(ReactiveStringRedisTemplate redis) {
        this.redis = redis;
    }

    public Mono<Void> append(UUID roomId, String json) {
        String key = key(roomId);
        return redis.opsForList().rightPush(key, json)
                .then(redis.expire(key, TTL))
                .then();
    }

    /** Events with seq strictly greater than {@code lastSeq} (lastSeq is 1-based, 0 = everything). */
    public Flux<String> replayAfter(UUID roomId, long lastSeq) {
        return redis.opsForList().range(key(roomId), Math.max(lastSeq, 0), -1);
    }

    public Mono<Long> size(UUID roomId) {
        return redis.opsForList().size(key(roomId));
    }

    private static String key(UUID roomId) {
        return "room:" + roomId + ":events";
    }
}
