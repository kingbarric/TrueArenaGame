package app.truearena.api.admin;

import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.BroadcastNotificationRepository;
import app.truearena.persistence.BroadcastNotificationRow;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.util.UUID;

/** Backs the broadcast composer page — see {@link BroadcastSchedulerService} for the actual send. */
@Service
public class AdminBroadcastService {

    private final BroadcastNotificationRepository broadcasts;

    public AdminBroadcastService(BroadcastNotificationRepository broadcasts) {
        this.broadcasts = broadcasts;
    }

    public Mono<UUID> create(String title, String body, String createdByAdmin, Instant scheduledFor) {
        String cleanTitle = title == null ? "" : title.strip();
        String cleanBody = body == null ? "" : body.strip();
        if (cleanTitle.isEmpty() || cleanBody.isEmpty()) {
            return Mono.error(ApiExceptions.badRequest("title and body are required"));
        }
        return broadcasts.save(BroadcastNotificationRow.draft(cleanTitle, cleanBody, createdByAdmin, scheduledFor))
                .map(BroadcastNotificationRow::id);
    }

    public Flux<BroadcastNotificationRow> recent() {
        return broadcasts.findTop50ByOrderByCreatedAtDesc();
    }

    public Mono<Void> cancelIfPending(UUID id) {
        return broadcasts.findById(id)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such broadcast")))
                .flatMap(b -> BroadcastNotificationRow.PENDING.equals(b.status())
                        ? broadcasts.save(b.withStatus("failed", null)).then() // "cancelled" shares the non-pending bucket
                        : Mono.error(ApiExceptions.conflict("already " + b.status())));
    }
}
