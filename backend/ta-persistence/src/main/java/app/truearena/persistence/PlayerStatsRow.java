package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * One row per {@code (group_id, user_id)}; {@code group_id == null} is the lifetime
 * rollup. Only the lifetime row is written today (ad-hoc games have no group) — see
 * {@code GameOrchestrator.updateStats}. {@code timesFirstAccused} and the win-streak
 * columns exist in the schema but aren't computed anywhere yet.
 */
@Table("player_stats")
public record PlayerStatsRow(
        @Id UUID id,
        @Column("group_id") UUID groupId,
        @Column("user_id") UUID userId,
        @Column("games_played") int gamesPlayed,
        int wins,
        @Column("traitor_games") int traitorGames,
        @Column("traitor_wins") int traitorWins,
        @Column("times_first_accused") int timesFirstAccused,
        @Column("current_win_streak") int currentWinStreak,
        @Column("longest_win_streak") int longestWinStreak,
        @Column("updated_at") Instant updatedAt
) {
    public static PlayerStatsRow lifetimeZero(UUID userId) {
        return new PlayerStatsRow(null, null, userId, 0, 0, 0, 0, 0, 0, 0, Instant.now());
    }

    /** Folds one finished game's outcome for this player into a running total. */
    public PlayerStatsRow plusGame(boolean won, boolean wasTraitor) {
        int newStreak = won ? currentWinStreak + 1 : 0;
        return new PlayerStatsRow(id, groupId, userId,
                gamesPlayed + 1,
                wins + (won ? 1 : 0),
                traitorGames + (wasTraitor ? 1 : 0),
                traitorWins + (wasTraitor && won ? 1 : 0),
                timesFirstAccused,
                newStreak,
                Math.max(longestWinStreak, newStreak),
                Instant.now());
    }
}
