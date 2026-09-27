package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface FriendRepository extends ReactiveCrudRepository<FriendRow, UUID> {
    Mono<FriendRow> findByLowUserIdAndHighUserId(UUID lowUserId, UUID highUserId);

    /** Every row involving this user, either side of the pair, any status. */
    Flux<FriendRow> findByLowUserIdOrHighUserId(UUID lowUserId, UUID highUserId);
}
