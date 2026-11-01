package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface RoomMemberRepository extends ReactiveCrudRepository<RoomMemberRow, UUID> {
    /**
     * In the order they sat down — that's the seating, so turn order and the lobby list stay put.
     * Collect it before querying per seat: {@code concatMap} asks for one row at a time, so the
     * open result keeps its pooled connection while each inner query waits for another one, and
     * a burst of lobbies filling with Cyber Agents took the whole pool and froze the server.
     */
    @Query("SELECT * FROM room_members WHERE room_id = :roomId ORDER BY joined_at, user_id")
    Flux<RoomMemberRow> findByRoomId(UUID roomId);

    Mono<RoomMemberRow> findByRoomIdAndUserId(UUID roomId, UUID userId);

    Mono<Long> countByRoomId(UUID roomId);

    Mono<Void> deleteByRoomIdAndUserId(UUID roomId, UUID userId);

    Mono<Void> deleteByRoomId(UUID roomId);
}
