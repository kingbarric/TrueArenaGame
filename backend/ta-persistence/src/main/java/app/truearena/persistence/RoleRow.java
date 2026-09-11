package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.util.UUID;

@Table("roles")
public record RoleRow(
        @Id UUID id,
        @Column("game_session_id") UUID gameSessionId,
        @Column("user_id") UUID userId,
        @Column("role_type") String roleType
) {
    public static RoleRow of(UUID gameSessionId, UUID userId, String roleType) {
        return new RoleRow(null, gameSessionId, userId, roleType);
    }
}
