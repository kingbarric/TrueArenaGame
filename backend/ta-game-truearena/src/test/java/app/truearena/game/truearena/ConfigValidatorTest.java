package app.truearena.game.truearena;

import app.truearena.engine.GameConfig;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class ConfigValidatorTest {

    @Test
    void everyShippedPresetIsValid() {
        for (Presets.Mode m : Presets.ALL) {
            ConfigValidator.Result r = ConfigValidator.validate(m.config());
            assertThat(r.ok()).as("%s: %s", m.slug(), r.errors()).isTrue();
        }
    }

    @Test
    void presetSlugsAreUnique() {
        assertThat(Presets.ALL.stream().map(Presets.Mode::slug).distinct().count()).isEqualTo(Presets.ALL.size());
    }

    @Test
    void playersOutsideRangeNeedsAdminOverride() {
        GameConfig c = Presets.CLASSIC_CONSPIRACY.config();               // 6–10
        GameConfig tooBig = withTable(c, new GameConfig.Table(14, 6, 10, false, c.table().traitorCurve()));
        assertThat(ConfigValidator.validate(tooBig).ok()).isFalse();

        GameConfig overridden = withTable(c, new GameConfig.Table(14, 6, 10, true, List.of(List.of(6, 3))));
        ConfigValidator.Result r = ConfigValidator.validate(overridden);
        assertThat(r.ok()).as("%s", r.errors()).isTrue();
        assertThat(r.warnings()).anyMatch(w -> w.contains("recommended"));
    }

    @Test
    void unknownTwistIsRejected() {
        GameConfig c = withTwists(Presets.CLASSIC_CONSPIRACY.config(), Map.of("teleport", Map.of()));
        assertThat(ConfigValidator.validate(c).errors()).anyMatch(e -> e.contains("unknown twist"));
    }

    @Test
    void wrongCatalogVersionIsRejected() {
        GameConfig c = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig bad = new GameConfig(99, c.preset(), c.table(), c.timers(), c.nightKill(), c.revealOnElimination(),
                c.tieBreak(), c.secondTie(), c.suddenDeathSeconds(), c.afk(), c.voteReveal(), c.endgameVeil(), c.twists());
        assertThat(ConfigValidator.validate(bad).errors()).anyMatch(e -> e.contains("catalogVersion"));
    }

    @Test
    void badEnumIsRejected() {
        GameConfig c = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig bad = new GameConfig(c.catalogVersion(), c.preset(), c.table(), c.timers(), c.nightKill(),
                "sometimes", c.tieBreak(), c.secondTie(), c.suddenDeathSeconds(), c.afk(), c.voteReveal(),
                c.endgameVeil(), c.twists());
        assertThat(ConfigValidator.validate(bad).errors()).anyMatch(e -> e.contains("revealOnElimination"));
    }

    private static GameConfig withTable(GameConfig c, GameConfig.Table t) {
        return new GameConfig(c.catalogVersion(), c.preset(), t, c.timers(), c.nightKill(), c.revealOnElimination(),
                c.tieBreak(), c.secondTie(), c.suddenDeathSeconds(), c.afk(), c.voteReveal(), c.endgameVeil(), c.twists());
    }

    private static GameConfig withTwists(GameConfig c, Map<String, Map<String, Object>> tw) {
        return new GameConfig(c.catalogVersion(), c.preset(), c.table(), c.timers(), c.nightKill(), c.revealOnElimination(),
                c.tieBreak(), c.secondTie(), c.suddenDeathSeconds(), c.afk(), c.voteReveal(), c.endgameVeil(), tw);
    }
}
