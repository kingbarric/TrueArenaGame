package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.Collection;
import java.util.UUID;

public interface DeviceTokenRepository extends ReactiveCrudRepository<DeviceTokenRow, UUID> {
    Flux<DeviceTokenRow> findByUserIdIn(Collection<UUID> userIds);

    Mono<DeviceTokenRow> findByToken(String token);

    Mono<Void> deleteByToken(String token);

    Mono<Void> deleteByUserIdAndToken(UUID userId, String token);
}
