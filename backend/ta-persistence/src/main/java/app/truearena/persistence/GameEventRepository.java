package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface GameEventRepository extends ReactiveCrudRepository<GameEventRow, UUID> {
    Mono<GameEventRow> findByGameSessionIdAndSeq(UUID gameSessionId, long seq);
}
