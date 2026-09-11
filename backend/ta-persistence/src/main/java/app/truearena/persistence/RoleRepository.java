package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;

import java.util.UUID;

public interface RoleRepository extends ReactiveCrudRepository<RoleRow, UUID> {
    Flux<RoleRow> findByGameSessionId(UUID gameSessionId);
}
