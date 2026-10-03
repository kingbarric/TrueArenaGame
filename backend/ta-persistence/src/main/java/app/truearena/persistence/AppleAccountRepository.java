package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Modifying;
import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface AppleAccountRepository extends ReactiveCrudRepository<AppleAccountRow, String> {
    Mono<AppleAccountRow> findByUserId(UUID userId);

    @Modifying
    @Query("INSERT INTO apple_accounts (subject, user_id) VALUES (:subject, :userId)")
    Mono<Integer> link(String subject, UUID userId);
}
