package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("users")
public record UserRow(
        @Id UUID id,
        @Column("display_name") String displayName,
        @Column("avatar_url") String avatarUrl,
        String phone,
        @Column("created_at") Instant createdAt
) {
    public static UserRow newUser(String phone, String displayName) {
        return new UserRow(null, displayName, null, phone, null);
    }
}
