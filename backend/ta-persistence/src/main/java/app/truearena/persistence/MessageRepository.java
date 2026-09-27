package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface MessageRepository extends ReactiveCrudRepository<MessageRow, UUID> {
    Flux<MessageRow> findByConversationIdOrderByCreatedAtDesc(UUID conversationId, org.springframework.data.domain.Pageable pageable);

    Mono<MessageRow> findFirstByConversationIdOrderByCreatedAtDesc(UUID conversationId);
}
