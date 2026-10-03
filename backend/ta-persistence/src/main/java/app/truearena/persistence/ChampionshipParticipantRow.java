package app.truearena.persistence;

import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("championship_participants")
public record ChampionshipParticipantRow(@Column("championship_id") UUID championshipId,
                                         @Column("user_id") UUID userId, int slot,
                                         @Column("joined_at") Instant joinedAt) {
}
