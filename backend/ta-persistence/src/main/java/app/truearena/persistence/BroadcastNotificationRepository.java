package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface BroadcastNotificationRepository extends ReactiveCrudRepository<BroadcastNotificationRow, UUID> {

    /** Pending broadcasts whose send time has arrived — polled by BroadcastSchedulerService. */
    @Query("SELECT * FROM broadcast_notifications WHERE status = 'pending' "
            + "AND (scheduled_for IS NULL OR scheduled_for <= now())")
    Flux<BroadcastNotificationRow> findDue();

    /**
     * Atomically flips pending -> sending and reports whether this caller
     * actually won the claim (1) or someone else already had it (0) — the
     * WHERE clause and the row count come from one statement, same no-race
     * pattern as {@code UserRepository.adjustCoins}. Needed because
     * {@code @Scheduled(fixedDelay=...)} only waits for the *method* to
     * return, not for a fire-and-forget reactive chain inside it to finish —
     * so two ticks can otherwise both see the same row as still "pending".
     */
    @Query("UPDATE broadcast_notifications SET status = 'sending' WHERE id = :id AND status = 'pending'")
    Mono<Long> claim(UUID id);

    Flux<BroadcastNotificationRow> findTop50ByOrderByCreatedAtDesc();
}
