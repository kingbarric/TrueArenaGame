package app.truearena.api.competitive;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class AchievementRulesTest {

    @Test
    @DisplayName("first ranked win")
    void firstWin() {
        assertThat(AchievementRules.earned(true, 1, 1, null)).containsExactly(AchievementType.FIRST_RANKED_WIN);
    }

    @Test
    @DisplayName("a loss before any win earns nothing")
    void nothingYet() {
        assertThat(AchievementRules.earned(false, 0, 0, null)).isEmpty();
    }

    @Test
    @DisplayName("win milestones accumulate")
    void winMilestones() {
        assertThat(AchievementRules.earned(true, 100, 1, null)).contains(
                AchievementType.FIRST_RANKED_WIN, AchievementType.WINS_10, AchievementType.WINS_100)
                .doesNotContain(AchievementType.WINS_1000);
    }

    @Test
    @DisplayName("streak badges at 10 and 25")
    void streaks() {
        assertThat(AchievementRules.earned(true, 30, 9, null)).doesNotContain(AchievementType.STREAK_10);
        assertThat(AchievementRules.earned(true, 30, 10, null)).contains(AchievementType.STREAK_10);
        assertThat(AchievementRules.earned(true, 30, 25, null)).contains(AchievementType.STREAK_10, AchievementType.STREAK_25);
    }

    @Test
    @DisplayName("beating ranked players: top 100, top 10, and #1 are nested")
    void topPlayerVictories() {
        assertThat(AchievementRules.earned(true, 5, 1, 101)).doesNotContain(AchievementType.DEFEATED_TOP_100);
        assertThat(AchievementRules.earned(true, 5, 1, 100)).contains(AchievementType.DEFEATED_TOP_100)
                .doesNotContain(AchievementType.DEFEATED_TOP_10);
        assertThat(AchievementRules.earned(true, 5, 1, 1)).contains(
                AchievementType.DEFEATED_TOP_100, AchievementType.DEFEATED_TOP_10, AchievementType.DEFEATED_NO_1);
    }

    @Test
    @DisplayName("a top-player badge needs a win, not a shared result")
    void drawWithTopPlayerIsNotADefeat() {
        assertThat(AchievementRules.earned(false, 5, 0, 1)).doesNotContain(AchievementType.DEFEATED_NO_1);
    }
}
