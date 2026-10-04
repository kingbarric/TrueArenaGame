package app.truearena.persistence;

import io.r2dbc.postgresql.codec.Json;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("user_notifications")
public record UserNotificationRow(
        @Id UUID id,
        @Column("user_id") UUID userId,
        String type,
        String title,
        String body,
        Json data,
        @Column("created_at") Instant createdAt,
        @Column("read_at") Instant readAt
) {
    public static UserNotificationRow of(UUID userId, String type, String title, String body, String dataJson) {
        return new UserNotificationRow(null, userId, type, title, body, Json.of(dataJson), null, null);
    }
}
