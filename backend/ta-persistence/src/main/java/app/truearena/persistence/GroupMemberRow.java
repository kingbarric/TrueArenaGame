package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("group_members")
public record GroupMemberRow(
        @Id UUID id,
        @Column("group_id") UUID groupId,
        @Column("user_id") UUID userId,
        String role,
        @Column("joined_at") Instant joinedAt
) {
    public static GroupMemberRow of(UUID groupId, UUID userId, String role) {
        return new GroupMemberRow(null, groupId, userId, role, null);
    }
}
