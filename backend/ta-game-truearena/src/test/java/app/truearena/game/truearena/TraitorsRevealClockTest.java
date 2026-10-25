package app.truearena.game.truearena;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameRunner;
import app.truearena.engine.GameState;
import app.truearena.engine.Phase;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A Traitors table runs itself: every phase but Results has a clock, so a host
 * who looks away can't leave everyone stuck on a reveal screen.
 */
class TraitorsRevealClockTest {

    private final TrueArenaModule module = new TrueArenaModule();

    private int seconds(GameConfig config, String phase) {
        return module.definePhases(config).stream().filter(p -> p.name().equals(phase))
                .findFirst().orElseThrow().timerSeconds();
    }

    @Test
    void everyPhaseButResultsHasAClock() {
        for (Presets.Mode mode : Presets.ALL) {
            for (Phase p : module.definePhases(mode.config())) {
                if ("Results".equals(p.name())) {
                    assertThat(p.timed()).as("%s in %s", p.name(), mode.slug()).isFalse();
                } else {
                    assertThat(p.timed()).as("%s in %s", p.name(), mode.slug()).isTrue();
                }
            }
        }
    }

    @Test
    void revealBeatsAreShortAndTheMorningWaitsLongerForALastWill() {
        GameConfig plain = Presets.CLASSIC_CONSPIRACY.config();
        assertThat(seconds(plain, "RoleReveal")).isEqualTo(TrueArenaModule.REVEAL_SECONDS);
        assertThat(seconds(plain, "Elimination")).isEqualTo(TrueArenaModule.REVEAL_SECONDS);
        assertThat(seconds(plain, "WinCheck")).isEqualTo(TrueArenaModule.REVEAL_SECONDS);
        assertThat(seconds(plain, "VoteReview")).isEqualTo(TrueArenaModule.VOTE_REVIEW_SECONDS);
        assertThat(seconds(plain, "MorningReveal")).isEqualTo(TrueArenaModule.MORNING_SECONDS);

        GameConfig withWill = new GameConfig(plain.catalogVersion(), plain.preset(), plain.table(), plain.timers(),
                plain.nightKill(), plain.revealOnElimination(), plain.tieBreak(), plain.secondTie(),
                plain.suddenDeathSeconds(), plain.afk(), plain.voteReveal(), plain.endgameVeil(),
                Map.of("last_will", Map.of()));
        assertThat(seconds(withWill, "MorningReveal")).isEqualTo(TrueArenaModule.MORNING_LAST_WILL_SECONDS);
    }

    @Test
    void theRoleRevealMovesOnWhenItsClockRunsOut() {
        GameConfig config = Presets.CLASSIC_CONSPIRACY.config();
        GameState s = module.initialState(List.of("p1", "p2", "p3", "p4", "p5", "p6"), config, RandomSource.seeded(3));
        assertThat(s.phase()).isEqualTo("RoleReveal");

        GameState next = new GameRunner(module).elapse(s, "RoleReveal").state();

        assertThat(next.phase()).isEqualTo("Night");
    }

    @Test
    void theHostCanEndTheGameEarlyWithNoWinnerAndEveryRoleShown() {
        GameConfig config = Presets.BLOOD_MOON.config();
        GameRunner runner = new GameRunner(module);
        GameState s = module.initialState(List.of("p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8"), config,
                RandomSource.seeded(5));
        s = runner.elapse(s, "RoleReveal").state();

        GameRunner.Step ended = runner.apply(s, PlayerAction.of("p1", "END_GAME", Map.of()));

        assertThat(ended.state().finished()).isTrue();
        assertThat(ended.state().phase()).isEqualTo("Results");
        assertThat(module.checkWinCondition(ended.state())).as("no winner, so no result or rewards").isEmpty();
        assertThat(ended.events()).extracting(e -> e.type()).containsExactly("GAME_ENDED_BY_HOST", "FULL_REVEAL");
        assertThat((Map<?, ?>) ended.events().get(1).payload().get("roles")).hasSize(8);
        // Over is over: nothing moves it on again.
        assertThat(runner.apply(ended.state(), PlayerAction.of("p1", "ADVANCE_PHASE", Map.of())).state().phase())
                .isEqualTo("Results");
    }
}
