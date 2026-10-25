package app.truearena.game.ludo;

import app.truearena.engine.*;
import org.junit.jupiter.api.Test;

import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

class LudoExpectimaxSearchTest {
    private final LudoModule game = new LudoModule();
    private final LudoExpectimaxSearch.Limits generous = new LudoExpectimaxSearch.Limits(1, 8, 50000, 1000);

    private LudoState table(List<Integer> mine, List<Integer> other, List<Integer> dice) {
        return new LudoState("Turn", 1, List.of("bot", "other"), Map.of("bot", mine, "other", other), 0, dice,
                0, 0, 728, null, Set.of(), Set.of(), List.of(), new LudoConfig(60, mine.size()));
    }

    private Map<String, Object> view(LudoState state) { return game.visibleStateFor(state, state.turnPlayer()).data(); }

    @Test void futureRollUsesTheActualProbabilityOfAtLeastOneOneAcrossTwoDice() {
        LudoState state = table(List.of(0, 56, 56, 56), List.of(55, 56, 56, 56), List.of(1));
        var decision = LudoExpectimaxSearch.choose(view(state), "bot", generous);
        assertThat(decision.completedRollHorizon()).isEqualTo(1);
        assertThat(decision.chanceOutcomes()).isEqualTo(21);
        // Opponent wins iff either die is 1: 11/36. Remaining 25/36 leave the board unchanged.
        double quietPosition = (20 + 1 + 3 * 200) - .6 * (90 + 5 * 6 + 3 * 200);
        assertThat(decision.expectedUtility()).isCloseTo((-100000 * 11 + quietPosition * 25) / 36, within(.00001));
        game.onPlayerAction(state, decision.action().orElseThrow());
    }

    @Test void usesBothKnownDiceBeforeEndingItsHorizonAndCanReleaseThenMove() {
        LudoState state = table(List.of(-1, -1, -1, -1), List.of(-1, -1, -1, -1), List.of(4, 6));
        var zeroFuture = new LudoExpectimaxSearch.Limits(0, 1, 1000, 1000);
        var decision = LudoExpectimaxSearch.choose(view(state), "bot", zeroFuture);
        assertThat(decision.action().orElseThrow().data()).containsEntry("die", 6);
        assertThat(decision.completedRollHorizon()).isZero();
        assertThat(decision.chanceOutcomes()).isZero();
        LudoState released = (LudoState) game.onPlayerAction(state, decision.action().orElseThrow());
        decision = LudoExpectimaxSearch.choose(view(released), "bot", zeroFuture);
        LudoState moved = (LudoState) game.onPlayerAction(released, decision.action().orElseThrow());
        assertThat(moved.pieces().get("bot")).contains(4);
        assertThat(moved.turnPlayer()).isEqualTo("other");
    }

    @Test void prefersFinishingATokenAndCapturingUsesTheGamesFinishOnCaptureRule() {
        LudoState state = table(List.of(55, 10, -1, -1), List.of(-1, -1, -1, -1), List.of(1));
        var decision = LudoExpectimaxSearch.choose(view(state), "bot", generous);
        assertThat(decision.action().orElseThrow().data()).containsEntry("token", 0);
        state = table(List.of(24, 0, -1, -1), List.of(1, -1, -1, -1), List.of(3));
        decision = LudoExpectimaxSearch.choose(view(state), "bot", generous);
        LudoState after = (LudoState) game.onPlayerAction(state, decision.action().orElseThrow());
        assertThat(after.pieces().get("bot")).contains(56);
        assertThat(after.pieces().get("other")).containsOnly(-1);
    }

    @Test void hiddenSeedAndSuggestedFutureDiceCannotChangeTheSearch() {
        LudoState state = table(List.of(12, 30, -1, -1), List.of(3, 18, -1, -1), List.of(2, 5));
        Map<String, Object> visible = new HashMap<>(view(state));
        var a = LudoExpectimaxSearch.choose(visible, "bot", generous);
        visible.put("seed", 777); visible.put("nextDice", List.of(6, 6)); visible.put("rollCount", 91);
        var b = LudoExpectimaxSearch.choose(visible, "bot", generous);
        assertThat(a.completedRollHorizon()).isEqualTo(1);
        assertThat(b.completedRollHorizon()).isEqualTo(1);
        assertThat(a.action().orElseThrow().data()).isEqualTo(b.action().orElseThrow().data());
        assertThat(a.expectedUtility()).isEqualTo(b.expectedUtility());
    }

    @Test void bonusRollsAndEliminatedPlayersSurviveVisibleStateReconstruction() {
        List<String> players = List.of("bot", "gone", "other");
        LudoState state = new LudoState("Turn", 1, players, Map.of("bot", List.of(0, -1, -1, -1),
                "gone", List.of(2, -1, -1, -1), "other", List.of(9, -1, -1, -1)), 0, List.of(1), 0, 1, 999,
                null, Set.of("gone"), Set.of(), List.of(), LudoConfig.defaults());
        LudoState parsed = LudoExpectimaxSearch.fromView(view(state), "bot").orElseThrow();
        assertThat(parsed.seed()).isZero();
        assertThat(parsed.bonusRolls()).isEqualTo(1);
        assertThat(parsed.eliminated()).containsExactly("gone");
        var decision = LudoExpectimaxSearch.choose(view(state), "bot", generous);
        LudoState after = (LudoState) game.onPlayerAction(state, decision.action().orElseThrow());
        assertThat(after.turnPlayer()).isEqualTo("bot");
        assertThat(decision.chanceOutcomes()).isPositive();
    }

    @Test void boundedAndInterruptedSearchKeepsALegalCompletedChoice() {
        LudoState state = table(List.of(4, 20, 31, -1), List.of(5, 21, 36, -1), List.of(3, 6));
        var result = LudoExpectimaxSearch.choose(view(state), "bot", new LudoExpectimaxSearch.Limits(3, 8, 1, 1000));
        assertThat(result.nodes()).isLessThanOrEqualTo(1);
        game.onPlayerAction(state, result.action().orElseThrow());
        Thread.currentThread().interrupt();
        try {
            result = LudoExpectimaxSearch.choose(view(state), "bot", generous);
            assertThat(result.nodes()).isZero();
            assertThat(Thread.currentThread().isInterrupted()).isTrue();
        } finally { Thread.interrupted(); }
    }

    @Test void searchChanceBranchesMatchActualServerRollsAcrossSeeds() {
        for (int seed = 1; seed <= 24; seed++) {
            LudoState state = new LudoState("Turn", 1, List.of("bot", "other"),
                    Map.of("bot", List.of(55, -1, -1, -1), "other", List.of(-1, -1, -1, -1)),
                    0, List.of(), seed % 3, 0, seed, null, Set.of(), Set.of(), List.of(), LudoConfig.defaults());
            LudoState actual = (LudoState) game.onPlayerAction(state, PlayerAction.of("bot", "ROLL", Map.of()));
            GameEvent roll = actual.events().stream().filter(e -> e.type().equals("DICE_ROLLED")).findFirst().orElseThrow();
            @SuppressWarnings("unchecked") List<Integer> dice = (List<Integer>) roll.payload().get("dice");
            LudoState simulated = game.applyRolledDice(state, "simulation", dice);
            assertThat(simulated.pieces()).isEqualTo(actual.pieces());
            assertThat(simulated.dice()).isEqualTo(actual.dice());
            assertThat(simulated.turnIndex()).isEqualTo(actual.turnIndex());
            assertThat(simulated.bonusRolls()).isEqualTo(actual.bonusRolls());
            assertThat(simulated.rollCount()).isEqualTo(actual.rollCount());
        }
    }
}
