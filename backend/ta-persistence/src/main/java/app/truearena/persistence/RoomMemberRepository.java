package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface RoomMemberRepository extends ReactiveCrudRepository<RoomMemberRow, UUID> {
    Flux<RoomMemberRow> findByRoomId(UUID roomId);

    Mono<RoomMemberRow> findByRoomIdAndUserId(UUID roomId, UUID userId);

    Mono<Long> countByRoomId(UUID roomId);

    Mono<Void> deleteByRoomIdAndUserId(UUID roomId, UUID userId);

    Mono<Void> deleteByRoomId(UUID roomId);

    /**
     * How many still-running rooms this user belongs to. Used to refuse
     * deleting a Cyber Agent that's mid-game — removing a player from a
     * board that's being played would strand the other side.
     */
    @Query("SELECT COUNT(*) FROM room_members m JOIN rooms r ON r.id = m.room_id "
            + "WHERE m.user_id = :userId AND r.status <> 'ended'")
    Mono<Long> countLiveRoomsFor(UUID userId);
}
