package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("championship_matches")
public record ChampionshipMatchRow(@Id UUID id,
                                   @Column("championship_id") UUID championshipId,
                                   int round, int position,
                                   @Column("player_a") UUID playerA,
                                   @Column("player_b") UUID playerB,
                                   @Column("winner_id") UUID winnerId,
                                   String status,
                                   @Column("room_id") UUID roomId,
                                   @Column("game_number") int gameNumber,
                                   @Column("a_remaining_ms") long aRemainingMs,
                                   @Column("b_remaining_ms") long bRemainingMs,
                                   @Column("a_absent_since") Instant aAbsentSince,
                                   @Column("b_absent_since") Instant bAbsentSince,
                                   @Column("started_at") Instant startedAt,
                                   @Column("completed_at") Instant completedAt) {
    public static ChampionshipMatchRow pending(UUID championshipId, int round, int position, UUID a, UUID b) {
        return new ChampionshipMatchRow(null, championshipId, round, position, a, b, null,
                "pending", null, 1, 180000, 180000, null, null, null, null);
    }
}
