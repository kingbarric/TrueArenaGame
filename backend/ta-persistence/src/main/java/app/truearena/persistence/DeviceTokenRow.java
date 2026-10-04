package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("device_tokens")
public record DeviceTokenRow(
        @Id UUID id,
        @Column("user_id") UUID userId,
        String platform,
        String token,
        @Column("created_at") Instant createdAt,
        @Column("updated_at") Instant updatedAt
) {
    public static final String IOS = "ios";
    public static final String ANDROID = "android";

    public static DeviceTokenRow of(UUID userId, String platform, String token) {
        return new DeviceTokenRow(null, userId, platform, token, null, null);
    }

    public DeviceTokenRow reassignedTo(UUID userId) {
        // This is an UPDATE (id is already set), not an INSERT — the column's
        // DEFAULT now() only applies on insert, so updated_at must be given a
        // real value here or the save violates the NOT NULL constraint.
        return new DeviceTokenRow(id, userId, platform, token, createdAt, Instant.now());
    }
}
