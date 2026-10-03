package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("championships")
public record ChampionshipRow(@Id UUID id, String code, String name,
                              @Column("game_type") String gameType, int size, String visibility,
                              @Column("scheduled_at") Instant scheduledAt,
                              @Column("creator_id") UUID creatorId, String status,
                              @Column("current_round") int currentRound,
                              @Column("champion_id") UUID championId,
                              @Column("created_at") Instant createdAt,
                              @Column("completed_at") Instant completedAt) {
    public static ChampionshipRow create(String code, String name, int size, String visibility,
                                         Instant scheduledAt, UUID creatorId) {
        return new ChampionshipRow(null, code, name, "draughts", size, visibility, scheduledAt,
                creatorId, "lobby", 0, null, null, null);
    }
}
