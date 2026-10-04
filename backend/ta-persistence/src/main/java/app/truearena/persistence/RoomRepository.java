package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Flux;

import java.util.UUID;

public interface RoomRepository extends ReactiveCrudRepository<RoomRow, UUID> {

    @Query("SELECT r.* FROM rooms r JOIN room_members m ON m.room_id = r.id "
            + "WHERE m.user_id = :userId AND r.status IN ('lobby', 'in_game') "
            + "AND r.created_at >= NOW() - INTERVAL '7 days' "
            + "ORDER BY r.created_at DESC LIMIT 1")
    Flux<RoomRow> findRecentActiveForUser(UUID userId);

    Mono<RoomRow> findByCode(String code);
}
