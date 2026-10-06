package app.truearena.api.competitive;

import java.util.EnumSet;
import java.util.Set;

/**
 * Which achievements one finished ranked match earns a player. Pure: the
 * caller supplies the post-match counters and the opponent's pre-match rank,
 * so the rules are unit-testable and the awarding side
 * ({@code RatingService}) only has to insert idempotently.
 *
 * <p>Returns everything currently satisfied, not just what is new — awards
 * are {@code ON CONFLICT DO NOTHING}, so re-qualifying is harmless and a
 * missed award self-heals on the player's next ranked game.
 */
public final class AchievementRules {

    private AchievementRules() {
    }

    /**
     * @param won                   this player won this match outright
     * @param rankedWins            ranked wins after this match
     * @param currentStreak         ranked win streak after this match
     * @param bestOpponentGlobalRank the best (lowest) pre-match global rank among
     *                              opponents beaten in this match; null if none
     *                              of them were on the leaderboard
     */
    public static Set<AchievementType> earned(boolean won, int rankedWins, int currentStreak,
                                              Integer bestOpponentGlobalRank) {
        Set<AchievementType> earned = EnumSet.noneOf(AchievementType.class);
        if (rankedWins >= 1) earned.add(AchievementType.FIRST_RANKED_WIN);
        if (rankedWins >= 10) earned.add(AchievementType.WINS_10);
        if (rankedWins >= 100) earned.add(AchievementType.WINS_100);
        if (rankedWins >= 1000) earned.add(AchievementType.WINS_1000);
        if (currentStreak >= 10) earned.add(AchievementType.STREAK_10);
        if (currentStreak >= 25) earned.add(AchievementType.STREAK_25);
        if (won && bestOpponentGlobalRank != null) {
            if (bestOpponentGlobalRank <= 100) earned.add(AchievementType.DEFEATED_TOP_100);
            if (bestOpponentGlobalRank <= 10) earned.add(AchievementType.DEFEATED_TOP_10);
            if (bestOpponentGlobalRank == 1) earned.add(AchievementType.DEFEATED_NO_1);
        }
        return earned;
    }
}
