package app.truearena.persistence;

import org.springframework.data.domain.Pageable;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;

import java.util.UUID;

public interface CoinTransactionRepository extends ReactiveCrudRepository<CoinTransactionRow, UUID> {
    Flux<CoinTransactionRow> findByUserIdOrderByCreatedAtDesc(UUID userId, Pageable pageable);
}
