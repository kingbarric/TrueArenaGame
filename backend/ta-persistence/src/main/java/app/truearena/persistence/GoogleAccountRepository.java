package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.r2dbc.repository.Modifying;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface GoogleAccountRepository extends ReactiveCrudRepository<GoogleAccountRow, String> {
    Mono<GoogleAccountRow> findByUserId(UUID userId);

    @Modifying
    @Query("INSERT INTO google_accounts (subject, user_id) VALUES (:subject, :userId)")
    Mono<Integer> link(String subject, UUID userId);
}
