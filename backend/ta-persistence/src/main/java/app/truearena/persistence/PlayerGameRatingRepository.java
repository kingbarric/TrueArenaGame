package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

/**
 * Reads only. Writes go through {@code RatingService}'s explicit upsert so the
 * trigger-owned location columns are never clobbered by a stale entity save.
 */
public interface PlayerGameRatingRepository extends ReactiveCrudRepository<PlayerGameRatingRow, UUID> {
    Mono<PlayerGameRatingRow> findByUserIdAndGameType(UUID userId, String gameType);

    Flux<PlayerGameRatingRow> findByUserId(UUID userId);
}
