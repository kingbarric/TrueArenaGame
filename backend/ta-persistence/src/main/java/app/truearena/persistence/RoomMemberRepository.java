package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface RoomMemberRepository extends ReactiveCrudRepository<RoomMemberRow, UUID> {
    /** In the order they sat down — that's the seating, so turn order and the lobby list stay put. */
    @Query("SELECT * FROM room_members WHERE room_id = :roomId ORDER BY joined_at, user_id")
    Flux<RoomMemberRow> findByRoomId(UUID roomId);

    Mono<RoomMemberRow> findByRoomIdAndUserId(UUID roomId, UUID userId);

    Mono<Long> countByRoomId(UUID roomId);

    Mono<Void> deleteByRoomIdAndUserId(UUID roomId, UUID userId);

    Mono<Void> deleteByRoomId(UUID roomId);
}
