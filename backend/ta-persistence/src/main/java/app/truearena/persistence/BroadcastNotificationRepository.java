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
     * actually won the claim: a value means yes, empty means someone else
     * already had it — the WHERE clause and the result come from one
     * statement, same no-race pattern as {@code UserRepository.adjustCoins}.
     * Needs {@code RETURNING} (unlike a plain UPDATE) because Spring Data
     * R2DBC maps a query's return type from actual result *rows*, not the
     * driver's separate rows-updated count — without it this always
     * resolves empty, even when the UPDATE itself affected a row, which
     * silently skipped every send (the "stuck in sending forever" bug).
     * Needed because {@code @Scheduled(fixedDelay=...)} only waits for the
     * *method* to return, not for a fire-and-forget reactive chain inside
     * it to finish — so two ticks can otherwise both see the same row as
     * still "pending".
     */
    @Query("UPDATE broadcast_notifications SET status = 'sending' WHERE id = :id AND status = 'pending' RETURNING 1")
    Mono<Long> claim(UUID id);

    /**
     * Self-healing for a claimed row whose send never finished — a crash or
     * restart mid-send (or the blocking-call-on-the-wrong-thread bug this
     * once hit) leaves a row parked at "sending" forever otherwise, since
     * {@link #findDue()} only ever looks at "pending". Anything stuck for
     * more than a couple of minutes (sends normally resolve in well under
     * one) is marked failed so the admin can just re-send rather than it
     * silently blocking that broadcast forever.
     */
    @Query("UPDATE broadcast_notifications SET status = 'failed' "
            + "WHERE status = 'sending' AND created_at <= now() - interval '2 minutes'")
    Mono<Long> failStuckSending();

    Flux<BroadcastNotificationRow> findTop50ByOrderByCreatedAtDesc();
}
