package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface GameConfigPresetRepository extends ReactiveCrudRepository<GameConfigPresetRow, UUID> {

    Flux<GameConfigPresetRow> findByScope(String scope);

    Mono<GameConfigPresetRow> findByScopeAndSlug(String scope, String slug);

    Flux<GameConfigPresetRow> findByScopeAndOwnerUserId(String scope, UUID ownerUserId);

    Mono<Void> deleteByScope(String scope);
}
