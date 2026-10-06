package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * Glicko-2 state for one player in one game. There is no universal rating:
 * {@code (user_id, game_type)} is the unique key, so being elite at Draughts
 * says nothing about Chess.
 *
 * <p>{@code countryCode}/{@code regionCode} are a trigger-maintained copy of
 * the player's {@link CompetitiveProfileRow} location, so scoped leaderboards
 * can be partial-index scans. Never written from here — the trigger owns them.
 * {@code provisional} and {@code leaderboardEligible} are stored rather than
 * computed per read for the same reason.
 */
@Table("player_game_ratings")
public record PlayerGameRatingRow(
        @Id UUID id,
        @Column("user_id") UUID userId,
        @Column("game_type") String gameType,
        double rating,
        @Column("rating_deviation") double ratingDeviation,
        double volatility,
        @Column("peak_rating") double peakRating,
        @Column("rated_games_played") int ratedGamesPlayed,
        boolean provisional,
        @Column("leaderboard_eligible") boolean leaderboardEligible,
        @Column("country_code") String countryCode,
        @Column("region_code") String regionCode,
        @Column("last_rated_at") Instant lastRatedAt,
        @Column("created_at") Instant createdAt
) {
}
