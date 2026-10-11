package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface UserNotificationRepository extends ReactiveCrudRepository<UserNotificationRow, UUID> {

    Flux<UserNotificationRow> findTop50ByUserIdOrderByCreatedAtDesc(UUID userId);

    @Query("UPDATE user_notifications SET read_at = now() WHERE id = :id AND user_id = :userId RETURNING 1")
    Mono<Long> markRead(UUID id, UUID userId);

    @Query("DELETE FROM user_notifications WHERE id = :id AND user_id = :userId RETURNING 1")
    Mono<Long> deleteOwn(UUID id, UUID userId);

    @Query("SELECT count(*) FROM user_notifications WHERE user_id = :userId AND read_at IS NULL")
    Mono<Long> countUnread(UUID userId);
}
