package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.data.r2dbc.repository.Modifying;
import org.springframework.data.r2dbc.repository.Query;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.Collection;
import java.util.UUID;

public interface DeviceTokenRepository extends ReactiveCrudRepository<DeviceTokenRow, UUID> {
    Flux<DeviceTokenRow> findByUserIdIn(Collection<UUID> userIds);

    Mono<DeviceTokenRow> findByToken(String token);

    /** The token identifies one installation; registration and account switching
     * must remain atomic when bootstrap and refresh register concurrently. */
    @Modifying
    @Query("INSERT INTO device_tokens (user_id, platform, token) VALUES (:userId, :platform, :token) "
            + "ON CONFLICT (token) DO UPDATE SET user_id=EXCLUDED.user_id, "
            + "platform=EXCLUDED.platform, updated_at=now()")
    Mono<Integer> register(UUID userId, String platform, String token);

    Mono<Void> deleteByToken(String token);

    Mono<Void> deleteByUserIdAndToken(UUID userId, String token);
}
