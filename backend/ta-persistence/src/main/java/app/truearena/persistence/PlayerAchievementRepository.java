package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;

import java.util.UUID;

/** Reads only — awards are idempotent {@code ON CONFLICT DO NOTHING} inserts in {@code AchievementService}. */
public interface PlayerAchievementRepository extends ReactiveCrudRepository<PlayerAchievementRow, UUID> {
    Flux<PlayerAchievementRow> findByUserIdOrderByDisplayPriorityDescEarnedAtDesc(UUID userId);
}
