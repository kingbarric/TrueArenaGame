package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * Per-game competitive counters — RANKED matches only, so the stat line on a
 * profile or leaderboard can't be padded by beating Cyber Agents or a casual
 * alt. Casual human games land in {@code casualGames} instead. Counts only:
 * win rate is derived, tournament wins come from {@code championships}, and
 * everything is reconstructable from match_records + match_participants.
 */
@Table("player_game_stats")
public record PlayerGameStatsRow(
        @Id UUID id,
        @Column("user_id") UUID userId,
        @Column("game_type") String gameType,
        @Column("games_played") int gamesPlayed,
        int wins,
        int losses,
        int draws,
        @Column("current_win_streak") int currentWinStreak,
        @Column("best_win_streak") int bestWinStreak,
        @Column("top100_wins") int top100Wins,
        @Column("casual_games") int casualGames,
        @Column("last_played_at") Instant lastPlayedAt,
        @Column("updated_at") Instant updatedAt
) {
    public double winRate() {
        return gamesPlayed == 0 ? 0.0 : (double) wins / gamesPlayed;
    }
}
