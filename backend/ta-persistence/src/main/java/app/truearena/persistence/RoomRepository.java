package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface RoomRepository extends ReactiveCrudRepository<RoomRow, UUID> {
    Mono<RoomRow> findByCode(String code);
}
