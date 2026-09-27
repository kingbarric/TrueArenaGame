package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface PlayerStatsRepository extends ReactiveCrudRepository<PlayerStatsRow, UUID> {
    /** The lifetime rollup row (group_id IS NULL) for this user, if it exists yet. */
    Mono<PlayerStatsRow> findByUserIdAndGroupIdIsNull(UUID userId);
}
