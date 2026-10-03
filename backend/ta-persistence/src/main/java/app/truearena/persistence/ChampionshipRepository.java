package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface ChampionshipRepository extends ReactiveCrudRepository<ChampionshipRow, UUID> {
    Mono<ChampionshipRow> findByCode(String code);
    Flux<ChampionshipRow> findByVisibilityOrderByCreatedAtDesc(String visibility);
    Flux<ChampionshipRow> findByCreatorIdOrderByCreatedAtDesc(UUID creatorId);
}
