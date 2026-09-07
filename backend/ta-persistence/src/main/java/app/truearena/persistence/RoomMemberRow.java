package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("room_members")
public record RoomMemberRow(
        @Id UUID id,
        @Column("room_id") UUID roomId,
        @Column("user_id") UUID userId,
        String nickname,
        @Column("connection_status") String connectionStatus,
        @Column("ready_state") boolean readyState,
        @Column("joined_at") Instant joinedAt
) {
    public static RoomMemberRow of(UUID roomId, UUID userId, String nickname) {
        return new RoomMemberRow(null, roomId, userId, nickname, "connected", false, null);
    }
}
