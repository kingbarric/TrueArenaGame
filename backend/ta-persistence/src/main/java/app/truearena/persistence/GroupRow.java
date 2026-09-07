package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("groups")
public record GroupRow(
        @Id UUID id,
        String name,
        @Column("created_by") UUID createdBy,
        @Column("created_at") Instant createdAt
) {
    public static GroupRow create(String name, UUID createdBy) {
        return new GroupRow(null, name, createdBy, null);
    }
}
