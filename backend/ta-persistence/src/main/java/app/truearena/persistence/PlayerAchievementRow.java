package app.truearena.persistence;

import io.r2dbc.postgresql.codec.Json;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * One earned achievement. The catalog — label, icon, priority, rarity — lives
 * in code ({@code AchievementType}) so a new badge needs no migration and
 * can't drift from the logic that awards it; only the per-player fact is here.
 */
@Table("player_achievements")
public record PlayerAchievementRow(
        @Id UUID id,
        @Column("user_id") UUID userId,
        String type,
        @Column("game_type") String gameType,
        @Column("earned_at") Instant earnedAt,
        Json metadata,
        @Column("display_priority") int displayPriority,
        String rarity
) {
}
