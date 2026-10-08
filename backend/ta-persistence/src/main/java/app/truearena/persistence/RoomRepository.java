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

    @Query("SELECT r.* FROM rooms r WHERE r.host_id = :hostId AND r.game_type = :gameType "
            + "AND r.status = 'lobby' AND r.huud_session_id IS NULL AND NOT EXISTS (SELECT 1 FROM championship_matches cm WHERE cm.room_id = r.id) "
            + "ORDER BY r.created_at DESC LIMIT 1")
    Mono<RoomRow> findHostedLobby(UUID hostId, String gameType);

    @Query("SELECT 1 FROM pg_advisory_xact_lock(hashtextextended(:key, 0))")
    Mono<Integer> lockHostedLobby(String key);

    Mono<RoomRow> findByCode(String code);
}
