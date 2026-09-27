package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface RoomRepository extends ReactiveCrudRepository<RoomRow, UUID> {

    /**
     * Moves every room hosted by one user to another. Used when retiring a
     * Cyber Agent that an older build had promoted to host — rooms.host_id
     * has no cascade (deleting a person must never delete their rooms), so
     * the reference has to be moved before the row can go.
     */
    @Query("UPDATE rooms SET host_id = :newHostId WHERE host_id = :oldHostId")
    Mono<Long> reassignHost(UUID oldHostId, UUID newHostId);
    Mono<RoomRow> findByCode(String code);
}
