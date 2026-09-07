package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface GroupMemberRepository extends ReactiveCrudRepository<GroupMemberRow, UUID> {
    Flux<GroupMemberRow> findByGroupId(UUID groupId);

    Mono<GroupMemberRow> findByGroupIdAndUserId(UUID groupId, UUID userId);

    Mono<Boolean> existsByGroupIdAndUserId(UUID groupId, UUID userId);
}
