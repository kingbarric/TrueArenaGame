package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/** One row per successful sign-in/token-refresh — the raw signal behind DAU/WAU/MAU
 * and return-rate on the admin analytics dashboard. See {@code AuthController}. */
@Table("login_events")
public record LoginEventRow(
        @Id UUID id,
        @Column("user_id") UUID userId,
        String method,
        @Column("created_at") Instant createdAt
) {
    public static LoginEventRow of(UUID userId, String method) {
        return new LoginEventRow(null, userId, method, null);
    }
}
