package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("rooms")
public record RoomRow(
        @Id UUID id,
        String code,
        @Column("group_id") UUID groupId,
        @Column("host_id") UUID hostId,
        String status,
        @Column("created_at") Instant createdAt
) {
    public static RoomRow create(String code, UUID groupId, UUID hostId) {
        return new RoomRow(null, code, groupId, hostId, "lobby", null);
    }
}
