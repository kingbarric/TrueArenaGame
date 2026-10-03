package app.truearena.api.admin;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class AdminDtos {

    private AdminDtos() {
    }

    public record Overview(
            long totalUsers,
            long totalGuests,
            long totalVerified,
            long newUsersToday,
            long newUsers7d,
            long newUsers30d,
            long dau,
            long wau,
            long mau,
            double returnRateD1,
            double returnRateD7,
            long totalGamesPlayed,
            long gamesToday,
            long games7d,
            long coinsInCirculation,
            long coinsEverEarned,
            long coinsSpentTotal,
            long issuesLast24h,
            long issuesLast7d,
            List<GameTypeBreakdown> gameTypeBreakdown,
            List<IssueTypeCount> issuesByType) {
    }

    public record GameTypeBreakdown(String gameType, long sessions, long completed, double avgDurationSeconds) {
    }

    public record IssueTypeCount(String type, long count) {
    }

    public record UserRow(
            UUID id,
            String displayName,
            String username,
            String maskedContact,
            boolean isGuest,
            Instant createdAt,
            Instant lastLoginAt,
            long loginCount,
            int gamesPlayed,
            int wins,
            double winRate,
            long coinsBalance,
            long coinsEarnedLifetime,
            long coinsSpentTotal,
            long stakeNet,
            long issuesCount) {
    }

    public record UserPage(List<UserRow> items, long total, int page, int size) {
    }

    public record LoginEventView(Instant createdAt, String method) {
    }

    public record IssueEventView(Instant createdAt, String type, String detail) {
    }

    public record RecentGame(UUID sessionId, String gameType, Instant startedAt, Instant endedAt, String winningSide) {
    }

    public record UserDetail(
            UserRow summary,
            List<LoginEventView> recentLogins,
            List<RecentGame> recentGames,
            List<IssueEventView> recentIssues) {
    }

    public record IssuePage(List<IssueFeedRow> items, long total, int page, int size) {
    }

    public record IssueFeedRow(Instant createdAt, String type, String detail, UUID userId, String userDisplayName) {
    }

    public record RetentionDay(String cohortDate, long newUsers, Double d1ReturnPct, Double d7ReturnPct) {
    }
}
