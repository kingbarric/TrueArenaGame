package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface GameResultRepository extends ReactiveCrudRepository<GameResultRow, UUID> {
    Mono<GameResultRow> findByGameSessionId(UUID gameSessionId);
}
