package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface CompetitiveProfileRepository extends ReactiveCrudRepository<CompetitiveProfileRow, UUID> {
    Mono<CompetitiveProfileRow> findByUserId(UUID userId);
}
