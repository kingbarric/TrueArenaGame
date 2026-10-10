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
                              @Column("completed_at") Instant completedAt,
                              @Column("huud_space_id") UUID huudSpaceId,
                              @Column("round_timing") String roundTiming,
                              @Column("spectators_allowed") boolean spectatorsAllowed,
                              @Column("grace_seconds") int graceSeconds) {
    public static ChampionshipRow create(String code, String name, int size, String visibility,
                                         Instant scheduledAt, UUID creatorId) {
        return new ChampionshipRow(null, code, name, "draughts", size, visibility, scheduledAt,
                creatorId, "lobby", 0, null, null, null, null, "simultaneous", true, 180);
    }

    /** A championship inside a Huud: it starts the moment every place is filled. */
    public static ChampionshipRow inHuud(String code, String name, String gameType, int size, UUID huudSpaceId,
                                         UUID creatorId, String roundTiming, boolean spectatorsAllowed,
                                         int graceSeconds) {
        return new ChampionshipRow(null, code, name, gameType, size, "private", Instant.now(), creatorId,
                "lobby", 0, null, null, null, huudSpaceId, roundTiming, spectatorsAllowed, graceSeconds);
    }

    public boolean sequential() {
        return "sequential".equals(roundTiming);
    }
}
