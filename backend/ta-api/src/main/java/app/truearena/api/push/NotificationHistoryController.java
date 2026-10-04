package app.truearena.api.push;

import app.truearena.api.support.CurrentUser;
import app.truearena.persistence.UserNotificationRepository;
import app.truearena.persistence.UserNotificationRow;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/** The in-app Notifications page — the signed-in user's own history, not the admin broadcast composer. */
@RestController
@RequestMapping("/api/v1/notifications")
@Tag(name = "push")
public class NotificationHistoryController {

    private final UserNotificationRepository history;
    private final ObjectMapper mapper;

    public NotificationHistoryController(UserNotificationRepository history, ObjectMapper mapper) {
        this.history = history;
        this.mapper = mapper;
    }

    public record NotificationView(UUID id, String type, String title, String body, Map<String, String> data,
            Instant createdAt, Instant readAt) {
        static NotificationView from(UserNotificationRow row, ObjectMapper mapper) {
            Map<String, String> data;
            try {
                data = mapper.readValue(row.data().asString(), new TypeReference<>() {
                });
            } catch (Exception e) {
                data = Map.of();
            }
            return new NotificationView(row.id(), row.type(), row.title(), row.body(), data, row.createdAt(),
                    row.readAt());
        }
    }

    @GetMapping
    @Operation(summary = "The signed-in user's 50 most recent notifications, newest first")
    public Flux<NotificationView> list() {
        return CurrentUser.id()
                .flatMapMany(history::findTop50ByUserIdOrderByCreatedAtDesc)
                .map(row -> NotificationView.from(row, mapper));
    }

    @GetMapping("/unread-count")
    @Operation(summary = "How many of the signed-in user's notifications are unread")
    public Mono<Long> unreadCount() {
        return CurrentUser.id().flatMap(history::countUnread);
    }

    @PostMapping("/{id}/read")
    @Operation(summary = "Mark one of the signed-in user's own notifications read")
    public Mono<Void> markRead(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> history.markRead(id, uid)).then();
    }
}
