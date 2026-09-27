package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface ConversationRepository extends ReactiveCrudRepository<ConversationRow, UUID> {
    Mono<ConversationRow> findByDmLowUserIdAndDmHighUserId(UUID low, UUID high);

    Mono<ConversationRow> findByGroupId(UUID groupId);

    @Query("""
            SELECT * FROM conversations
            WHERE (type = 'dm' AND (dm_low_user_id = :userId OR dm_high_user_id = :userId))
               OR (type = 'group' AND group_id IN (SELECT group_id FROM group_members WHERE user_id = :userId))
            """)
    Flux<ConversationRow> findAllForMember(UUID userId);
}
