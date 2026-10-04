package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("broadcast_notifications")
public record BroadcastNotificationRow(
        @Id UUID id,
        String title,
        String body,
        @Column("created_by_admin") String createdByAdmin,
        @Column("scheduled_for") Instant scheduledFor,
        @Column("sent_at") Instant sentAt,
        String status,
        @Column("created_at") Instant createdAt
) {
    public static final String PENDING = "pending";
    public static final String SENDING = "sending";
    public static final String SENT = "sent";
    public static final String FAILED = "failed";

    public static BroadcastNotificationRow draft(String title, String body, String createdByAdmin, Instant scheduledFor) {
        return new BroadcastNotificationRow(null, title, body, createdByAdmin, scheduledFor, null, PENDING, null);
    }

    public BroadcastNotificationRow withStatus(String status, Instant sentAt) {
        return new BroadcastNotificationRow(id, title, body, createdByAdmin, scheduledFor, sentAt, status, createdAt);
    }
}
