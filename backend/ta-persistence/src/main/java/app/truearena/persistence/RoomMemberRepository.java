package app.truearena.persistence;

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
}
