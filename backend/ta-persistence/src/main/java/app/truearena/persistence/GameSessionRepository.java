package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface GameSessionRepository extends ReactiveCrudRepository<GameSessionRow, UUID> {
    Mono<GameSessionRow> findFirstByRoomIdOrderByStartedAtDesc(UUID roomId);
}
