package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/** A best-effort operational signal for the admin dashboard — deliberately small in
 * scope (currently: failed OTP verification), not a general error-tracking pipeline. */
@Table("issue_events")
public record IssueEventRow(
        @Id UUID id,
        @Column("user_id") UUID userId,
        String type,
        String detail,
        @Column("created_at") Instant createdAt
) {
    public static IssueEventRow of(UUID userId, String type, String detail) {
        return new IssueEventRow(null, userId, type, detail, null);
    }
}
