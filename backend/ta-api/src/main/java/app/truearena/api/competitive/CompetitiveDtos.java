package app.truearena.api.competitive;

import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Wire shapes for the competitive API. Ratings go out rounded to whole numbers
 * — the stored doubles are the source of truth, "1842.37" is noise to a player.
 */
public final class CompetitiveDtos {

    private CompetitiveDtos() {
    }

    public record FoundingView(String code, String label) {
        static FoundingView of(FoundingTier tier) {
            return tier == null ? null : new FoundingView(tier.name(), tier.label());
        }
    }

    /**
     * Where the player competes. {@code city} is only present on your own
     * profile, or on someone else's if they opted in — precise location is
     * never public by default.
     */
    public record LocationView(String countryCode, String countryName, String regionCode, String regionName,
                               String city, boolean cityPublic) {
    }

    /**
     * One rank on one board. {@code rank} is set only when {@code status} is
     * {@code "ranked"}; otherwise status says what's missing so the app can
     * show "Complete profile" or "5 / 10 placement games" instead of a number.
     */
    public record RankView(Integer rank, String status) {
        public static final String RANKED = "ranked";
        public static final String PROVISIONAL = "provisional";
        public static final String LOCATION_REQUIRED = "location_required";
        public static final String UNRATED = "unrated";
    }

    public record RanksView(RankView global, RankView country, RankView region) {
    }

    public record GameStatsView(int gamesPlayed, int wins, int losses, int draws, double winRate,
                                int currentWinStreak, int bestWinStreak, int top100Wins,
                                int tournamentWins, int casualGames) {
    }

    public record GameRecordView(
            String gameType,
            Integer rating,
            Integer peakRating,
            Integer ratingDeviation,
            boolean provisional,
            int placementGamesPlayed,
            int placementGamesRequired,
            RanksView ranks,
            GameStatsView stats,
            Instant lastRatedAt) {
    }

    public record AchievementView(String type, String label, String icon, String gameType,
                                  Instant earnedAt, String rarity, int displayPriority,
                                  Map<String, Object> metadata) {
    }

    public record CompetitiveProfileView(
            UUID userId,
            String username,
            String displayName,
            String avatarUrl,
            Long playhuudNumber,
            String playhuudId,
            FoundingView founding,
            LocationView location,
            /** Country and region both set — the state that unlocks every scoped board. */
            boolean profileComplete,
            /** Own profile only: when the ranking location can next be changed, if locked. */
            Instant locationLockedUntil,
            List<GameRecordView> games,
            List<AchievementView> achievements) {
    }

    public record UpdateLocationRequest(
            @Size(min = 2, max = 2) String countryCode,
            @Size(max = 16) String regionCode,
            /** Free-text region, only for countries whose regions aren't catalogued. */
            @Size(max = 60) String regionName,
            @Size(max = 60) String city,
            Boolean cityPublic) {
    }

    public record LeaderboardEntryView(
            int rank,
            UUID userId,
            String username,
            String displayName,
            String avatarUrl,
            Long playhuudNumber,
            String playhuudId,
            FoundingView founding,
            int rating,
            int peakRating,
            int gamesPlayed,
            double winRate,
            int tournamentWins,
            boolean provisional) {
    }

    public record LeaderboardView(
            String gameType,
            String scope,
            /** The country/region code this board is for; null for global and friends. */
            String scopeKey,
            String scopeName,
            int offset,
            List<LeaderboardEntryView> entries,
            /** The viewer's own standing on this board, pinned under the page. */
            LeaderboardEntryView me,
            /** Why the board is unavailable to this viewer, e.g. "location_required". */
            String unavailableReason) {
    }

    public record MatchOpponentView(UUID userId, String username, String displayName, String avatarUrl,
                                    boolean isBot, String outcome, Integer ratingBefore) {
    }

    public record MatchHistoryView(
            UUID matchId,
            String gameType,
            boolean ranked,
            String unrankedReason,
            String outcome,
            boolean draw,
            Instant completedAt,
            Long durationMs,
            UUID championshipId,
            Integer ratingBefore,
            Integer ratingAfter,
            Integer ratingDelta,
            List<MatchOpponentView> opponents) {
    }

    public record CountryView(String code, String name, boolean catalogued) {
    }

    public record RegionView(String code, String name) {
    }
}
