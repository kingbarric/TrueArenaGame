package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;

import java.util.UUID;

public interface GroupRepository extends ReactiveCrudRepository<GroupRow, UUID> {

    @Query("""
            SELECT g.* FROM groups g
            JOIN group_members m ON m.group_id = g.id
            WHERE m.user_id = :userId
            ORDER BY g.created_at DESC
            """)
    Flux<GroupRow> findAllForMember(UUID userId);
}
