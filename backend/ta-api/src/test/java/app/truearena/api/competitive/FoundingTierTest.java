package app.truearena.api.competitive;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class FoundingTierTest {

    @Test
    @DisplayName("tier boundaries are inclusive at 100, 1,000 and 10,000")
    void boundaries() {
        assertThat(FoundingTier.of(1L)).isEqualTo(FoundingTier.FOUNDING_100);
        assertThat(FoundingTier.of(100L)).isEqualTo(FoundingTier.FOUNDING_100);
        assertThat(FoundingTier.of(101L)).isEqualTo(FoundingTier.FOUNDING_1000);
        assertThat(FoundingTier.of(1_000L)).isEqualTo(FoundingTier.FOUNDING_1000);
        assertThat(FoundingTier.of(1_001L)).isEqualTo(FoundingTier.FOUNDING_10000);
        assertThat(FoundingTier.of(10_000L)).isEqualTo(FoundingTier.FOUNDING_10000);
        assertThat(FoundingTier.of(10_001L)).isNull();
    }

    @Test
    @DisplayName("no number (a bot) and nonsense numbers have no tier")
    void noNumber() {
        assertThat(FoundingTier.of(null)).isNull();
        assertThat(FoundingTier.of(0L)).isNull();
    }

    @Test
    @DisplayName("public format is #NNNNNN and keeps growing past six digits")
    void format() {
        assertThat(FoundingTier.formatNumber(1L)).isEqualTo("#000001");
        assertThat(FoundingTier.formatNumber(127L)).isEqualTo("#000127");
        assertThat(FoundingTier.formatNumber(8_421L)).isEqualTo("#008421");
        assertThat(FoundingTier.formatNumber(1_234_567L)).isEqualTo("#1234567");
        assertThat(FoundingTier.formatNumber(null)).isNull();
    }

    @Test
    @DisplayName("each founding tier renders through the achievement catalog")
    void foundingAchievements() {
        assertThat(AchievementType.founding(FoundingTier.FOUNDING_100)).isEqualTo(AchievementType.FOUNDING_100);
        assertThat(AchievementType.founding(null)).isNull();
    }
}
