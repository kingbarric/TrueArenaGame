package app.truearena.api.admin;

import app.truearena.persistence.BroadcastNotificationRow;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirements;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.util.UUID;

/**
 * Backs the /notvisible/broadcasts admin composer. Same {@link AdminKeyFilter}
 * gate as {@link AdminAnalyticsController} — not part of the app's own JWT auth,
 * never called by the mobile app.
 */
@RestController
@RequestMapping("/api/v1/admin/broadcasts")
@Tag(name = "admin", description = "Push-notification broadcast composer — gated by X-Admin-Key, not user auth")
@SecurityRequirements
public class AdminBroadcastController {

    private final AdminBroadcastService service;

    public AdminBroadcastController(AdminBroadcastService service) {
        this.service = service;
    }

    public record CreateBroadcastRequest(String title, String body, String createdByAdmin, Instant scheduledFor) {
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Author a broadcast push — sends on the next scheduler tick if scheduledFor is omitted")
    public Mono<UUID> create(@RequestBody CreateBroadcastRequest body) {
        return service.create(body.title(), body.body(), body.createdByAdmin(), body.scheduledFor());
    }

    @GetMapping
    @Operation(summary = "The 50 most recent broadcasts, newest first")
    public Flux<BroadcastNotificationRow> list() {
        return service.recent();
    }

    @DeleteMapping("/{id}")
    @Operation(summary = "Cancel a broadcast that hasn't sent yet")
    public Mono<Void> cancel(@PathVariable UUID id) {
        return service.cancelIfPending(id);
    }
}
