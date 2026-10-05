package app.truearena.game.goosi;

import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.Arrays;
import java.util.Random;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class GoosiModuleTest {

    private final GoosiModule module = new GoosiModule();
    private static final List<String> PLAYERS = List.of("south", "north");

    private GoosiState start() {
        return (GoosiState) module.initialState(
                PLAYERS, GoosiConfig.defaults(), RandomSource.seeded(1));
    }

    private GoosiState position(int[] pits, int southScore, int northScore, int turn) {
        return position(pits, southScore, northScore, turn, GoosiConfig.RELAY);
    }

    private GoosiState position(int[] pits, int southScore, int northScore, int turn, String mode) {
        GoosiState base = (GoosiState) module.initialState(
                PLAYERS, new GoosiConfig(4, 45, mode), RandomSource.seeded(1));
        GoosiState.Draft d = new GoosiState.Draft(base);
        d.pits = pits.clone();
        d.scores = new int[]{southScore, northScore};
        d.turnIndex = turn;
        d.phase = "TurnP" + turn;
        d.events.clear();
        d.seq = 0;
        return d.build();
    }

    private GoosiState sow(GoosiState state, int pit) {
        String actor = state.players.get(state.turnIndex);
        return (GoosiState) module.onPlayerAction(
                state, PlayerAction.of(actor, "SOW", Map.of("pit", pit)));
    }

    @Test
    void startsWithFourSeedsInEachOfTwelveHouses() {
        GoosiState state = start();

        assertThat(state.players).hasSize(2);
        assertThat(state.pits).hasSize(12).containsOnly(4);
        assertThat(state.owner).hasSize(12);
        assertThat(state.owner[0]).isEqualTo(state.owner[5]);
        assertThat(state.owner[6]).isEqualTo(state.owner[11]);
        assertThat(state.owner[0]).isNotEqualTo(state.owner[6]);
        assertThat(state.scores).containsExactly(0, 0);
    }

    @Test
    void rejectsAnyPlayerCountOtherThanTwo() {
        assertThatThrownBy(() -> module.initialState(
                List.of("solo"), GoosiConfig.defaults(), RandomSource.seeded(1)))
                .isInstanceOf(RuleViolation.class)
                .hasMessageContaining("exactly 2");
        assertThatThrownBy(() -> module.initialState(
                List.of("a", "b", "c", "d"), GoosiConfig.defaults(), RandomSource.seeded(1)))
                .isInstanceOf(RuleViolation.class);
    }

    @Test
    void lastSeedInEmptyHouseStopsAndPassesTheTurn() {
        GoosiState before = position(
                new int[]{2, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0}, 0, 0, 0);
        GoosiState after = sow(before, 0);

        assertThat(after.pits).containsExactly(0, 2, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0);
        assertThat(after.turnIndex).isEqualTo(1);
    }

    @Test
    void longSowIncludesItsStartingHouseOnTheNextLap() {
        GoosiState state = position(
                new int[]{12, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0}, 0, 0, 0);
        GoosiState after = sow(state, 0);

        assertThat(after.pits[0]).isEqualTo(1);
        assertThat(after.pits[6]).isEqualTo(2);
        assertThat(after.pits[11]).isEqualTo(1);
    }

    @Test
    void lastSeedInOccupiedHouseRelaysUntilAnEmptyHouse() {
        GoosiState state = position(
                new int[]{2, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0}, 0, 0, 0);
        GoosiState after = sow(state, 0);

        assertThat(after.pits).containsExactly(0, 1, 0, 1, 1, 0, 1, 0, 0, 0, 0, 0);
        assertThat(after.scores).containsExactly(0, 0);
        assertThat(after.events().stream().filter(e -> "SOWN".equals(e.type())).findFirst()
                .orElseThrow().payload().get("laps")).isEqualTo(List.of(List.of(1, 2), List.of(3, 4)));
    }

    @Test
    void completingFourCollectsFromOwnAndOpponentHousesMidSow() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 3, 3, 3, 0, 1, 0, 0, 0}, 0, 0, 0);
        GoosiState after = sow(state, 4);

        assertThat(after.pits[5]).isZero();
        assertThat(after.pits[6]).isZero();
        assertThat(after.pits[7]).isEqualTo(1);
        assertThat(after.scores[0]).isEqualTo(8);
        assertThat(after.events().stream().filter(e -> "SOWN".equals(e.type())).findFirst()
                .orElseThrow().payload().get("captures")).isEqualTo(Map.of("0:0", 5, "0:1", 6));
    }

    @Test
    void lastSeedCompletingFourIsCollectedAndEndsTheRelay() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 1, 3, 1, 0, 0, 0, 0}, 0, 0, 0);
        GoosiState after = sow(state, 5);

        assertThat(after.pits[6]).isZero();
        assertThat(after.scores[0]).isEqualTo(4);
        assertThat(after.finished()).isFalse();
    }

    @Test
    void anyNonEmptyOwnHouseIsLegalEvenIfOpponentRowIsEmpty() {
        GoosiState state = position(
                new int[]{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0}, 0, 0, 0);

        assertThat(GoosiModule.legalPits(state.pits, state.owner, state.players.get(0)))
                .containsExactly(0, 5);
    }

    @Test
    void gameEndsWhenNextPlayerHasNoHouseWithSeeds() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 1, 3, 0, 0, 0, 0, 0}, 0, 0, 0);

        GoosiState after = sow(state, 5);

        assertThat(after.finished()).isTrue();
        assertThat(after.pits).containsOnly(0);
        assertThat(after.scores).containsExactly(4, 0);
        assertThat(module.checkWinCondition(after)).isPresent();
    }

    @Test
    void uncollectedSeedsStayOnTheBoardWhenTheNextPlayerCannotMove() {
        GoosiState state = position(
                new int[]{1, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0}, 8, 4, 0);

        GoosiState after = sow(state, 0);

        assertThat(after.finished()).isTrue();
        assertThat(after.pits).containsExactly(0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0);
        assertThat(after.scores).containsExactly(8, 4);
        assertThat(module.checkWinCondition(after).orElseThrow().winningSide())
                .isEqualTo(state.players.get(0));
    }

    @Test
    void firstPlayerPastTwentyFourWinsImmediately() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 1, 3, 1, 0, 0, 0, 0}, 23, 18, 0);
        GoosiState after = sow(state, 5);

        assertThat(after.scores[0]).isEqualTo(27);
        assertThat(after.finished()).isTrue();
        assertThat(module.checkWinCondition(after)).isPresent();
    }

    @Test
    void visibleStateIncludesOnlyLegalHouseTaps() {
        GoosiState state = position(
                new int[]{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0}, 0, 0, 0);

        assertThat(module.visibleStateFor(state, state.players.get(0)).data())
                .containsEntry("legalPits", List.of(0, 5))
                .containsEntry("pitsPerPlayer", 6);
    }

    @Test
    void owareSowsOnceAndCapturesTwoOrThreeFromOpponentRow() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 1, 1, 5, 0, 0, 0, 0},
                0, 0, 0, GoosiConfig.OWARE);

        GoosiState after = sow(state, 5);

        assertThat(after.pits[6]).isZero();
        assertThat(after.scores[0]).isEqualTo(2);
        assertThat(after.turnIndex).isEqualTo(1);
    }

    @Test
    void owareCaptureChainsBackwardAcrossOpponentTwosAndThrees() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 3, 0, 1, 1, 4, 0, 0},
                0, 0, 0, GoosiConfig.OWARE);

        GoosiState after = sow(state, 5);

        assertThat(after.pits[8]).isZero();
        assertThat(after.pits[7]).isZero();
        assertThat(after.pits[6]).isEqualTo(1);
        assertThat(after.scores[0]).isEqualTo(4);
    }

    @Test
    void owareGrandSlamDoesNotCapture() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 6, 1, 1, 1, 1, 1, 1},
                0, 0, 0, GoosiConfig.OWARE);

        GoosiState after = sow(state, 5);

        assertThat(after.pits).containsExactly(0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2);
        assertThat(after.scores[0]).isZero();
    }

    @Test
    void owareRequiresFeedingAnEmptyOpponentRow() {
        GoosiState state = position(
                new int[]{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0},
                0, 0, 0, GoosiConfig.OWARE);

        assertThat(module.visibleStateFor(state, state.players.get(0)).data())
                .containsEntry("mode", GoosiConfig.OWARE)
                .containsEntry("legalPits", List.of(5));
        assertThatThrownBy(() -> sow(state, 0))
                .isInstanceOf(RuleViolation.class)
                .hasMessageContaining("feeds");
    }

    @Test
    void owareSweepsRemainingSeedsWhenNextPlayerCannotMove() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0},
                8, 4, 0, GoosiConfig.OWARE);

        GoosiState after = sow(state, 5);

        assertThat(after.finished()).isTrue();
        assertThat(after.pits).containsOnly(0);
        assertThat(after.scores).containsExactly(8, 5);
    }

    @Test
    void duplicateActionIdDoesNotSowTwice() {
        GoosiState state = start();
        String actor = state.players.get(0);
        int from = state.owner[0].equals(actor) ? 0 : 6;
        PlayerAction action = new PlayerAction("same-id", actor, "SOW", Map.of("pit", from));

        GameState once = module.onPlayerAction(state, action);
        GameState twice = module.onPlayerAction(once, action);

        assertThat(twice).isSameAs(once);
    }

    @Test
    void relayPlayConservesAllFortyEightSeedsAcrossManyTurns() {
        Random choices = new Random(19);
        for (int game = 0; game < 12; game++) {
            GoosiState state = (GoosiState) module.initialState(
                    PLAYERS, GoosiConfig.defaults(), RandomSource.seeded(game + 1));
            for (int turn = 0; turn < 100 && !state.finished(); turn++) {
                String actor = state.players.get(state.turnIndex);
                List<Integer> legal = GoosiModule.legalPits(state.pits, state.owner, actor);
                assertThat(legal).isNotEmpty();
                int[] beforeScores = state.scores.clone();
                state = sow(state, legal.get(choices.nextInt(legal.size())));
                assertThat(Arrays.stream(state.pits).sum() + Arrays.stream(state.scores).sum())
                        .as("game %s turn %s", game, turn).isEqualTo(48);
                assertThat(state.scores[0]).isGreaterThanOrEqualTo(beforeScores[0]);
                assertThat(state.scores[1]).isGreaterThanOrEqualTo(beforeScores[1]);
            }
        }
    }

    @Test
    void finalExpiredGraceForfeitsTheHeadToHeadGame() {
        GoosiState state = start();
        GoosiState graceA = (GoosiState) module.onPhaseElapsed(state, "TurnP0");
        GoosiState graceB = (GoosiState) module.onPhaseElapsed(graceA, "GraceP0a");
        GoosiState result = (GoosiState) module.onPhaseElapsed(graceB, "GraceP0b");

        assertThat(graceA.phase).isEqualTo("GraceP0a");
        assertThat(graceB.phase).isEqualTo("GraceP0b");
        assertThat(result.finished()).isTrue();
        assertThat(module.checkWinCondition(result)).isPresent();
    }

    // ---------------------------------------------------------------- playersToAct (push turn reminders)

    @Test
    void playersToActIsWhoeverIsOnTurn() {
        assertThat(module.playersToAct(start())).containsExactly("south");
        assertThat(module.playersToAct(position(new int[12], 0, 0, 1))).containsExactly("north");
    }

    @Test
    void playersToActIsEmptyOnceFinished() {
        GoosiState state = start();
        GoosiState graceA = (GoosiState) module.onPhaseElapsed(state, "TurnP0");
        GoosiState graceB = (GoosiState) module.onPhaseElapsed(graceA, "GraceP0a");
        GoosiState result = (GoosiState) module.onPhaseElapsed(graceB, "GraceP0b");
        assertThat(module.playersToAct(result)).isEmpty();
    }
}
