package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;

import java.util.UUID;

public interface GameResultRepository extends ReactiveCrudRepository<GameResultRow, UUID> {
}
