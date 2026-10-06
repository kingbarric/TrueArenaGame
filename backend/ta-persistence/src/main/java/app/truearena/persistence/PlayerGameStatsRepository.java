package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

/** Reads only — writes are atomic SQL increments in {@code RatingService}. */
public interface PlayerGameStatsRepository extends ReactiveCrudRepository<PlayerGameStatsRow, UUID> {
    Mono<PlayerGameStatsRow> findByUserIdAndGameType(UUID userId, String gameType);

    Flux<PlayerGameStatsRow> findByUserId(UUID userId);
}
