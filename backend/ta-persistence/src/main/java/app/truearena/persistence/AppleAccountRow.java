package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("apple_accounts")
public record AppleAccountRow(
        @Id String subject,
        @Column("user_id") UUID userId,
        @Column("created_at") Instant createdAt
) {
}
