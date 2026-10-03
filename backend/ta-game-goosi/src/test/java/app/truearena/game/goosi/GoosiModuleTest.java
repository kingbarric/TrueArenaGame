package app.truearena.game.goosi;

import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

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
        GoosiState.Draft d = new GoosiState.Draft(start());
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
    void startsAsAStandardTwelveHouseOwareBoard() {
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
    void oneMoveSowsOnceAndPassesTheTurn() {
        GoosiState before = start();
        int from = before.owner[0].equals(before.players.get(0)) ? 0 : 6;
        GoosiState after = sow(before, from);

        assertThat(after.pits[from]).isZero();
        for (int offset = 1; offset <= 4; offset++) {
            assertThat(after.pits[(from + offset) % 12]).isEqualTo(5);
        }
        assertThat(after.turnIndex).isEqualTo(1);
    }

    @Test
    void aLongSowSkipsItsStartingHouse() {
        GoosiState state = position(
                new int[]{12, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0}, 0, 0, 0);
        GoosiState after = sow(state, 0);

        assertThat(after.pits[0]).isZero();
        assertThat(after.pits[1]).isEqualTo(2);
        for (int pit = 2; pit < 12; pit++) {
            assertThat(after.pits[pit]).isEqualTo(pit == 6 ? 2 : 1);
        }
    }

    @Test
    void capturesTwoOrThreeFromTheOpponentsRow() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 1, 1, 4, 0, 0, 0, 0}, 0, 0, 0);
        GoosiState after = sow(state, 5);

        assertThat(after.pits[6]).isZero();
        assertThat(after.scores[0]).isEqualTo(2);
    }

    @Test
    void captureContinuesBackwardAcrossConsecutiveTwosAndThrees() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 3, 0, 1, 1, 4, 0, 0}, 0, 0, 0);
        GoosiState after = sow(state, 5);

        assertThat(after.pits[8]).isZero();
        assertThat(after.pits[7]).isZero();
        assertThat(after.pits[6]).isEqualTo(1);
        assertThat(after.scores[0]).isEqualTo(4);
    }

    @Test
    void aGrandSlamIsVoidButTheSowStillStands() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 6, 1, 1, 1, 1, 1, 1}, 0, 0, 0);
        GoosiState after = sow(state, 5);

        assertThat(after.pits).containsExactly(0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2);
        assertThat(after.scores[0]).isZero();
        assertThat(after.finished()).isFalse();
    }

    @Test
    void feedingMoveIsMandatoryWhenOpponentHasNoSeeds() {
        GoosiState state = position(
                new int[]{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0}, 0, 0, 0);

        assertThat(GoosiModule.legalPits(state.pits, state.owner, state.players.get(0)))
                .containsExactly(5);
        assertThatThrownBy(() -> sow(state, 0))
                .isInstanceOf(RuleViolation.class)
                .hasMessageContaining("feeds");
    }

    @Test
    void gameEndsWhenTheEmptyPlayerCannotBeFed() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0}, 0, 0, 0);

        GoosiState after = sow(state, 5);

        assertThat(after.finished()).isTrue();
        assertThat(after.pits).containsOnly(0);
        assertThat(after.scores).containsExactly(0, 1);
        assertThat(module.checkWinCondition(after)).isPresent();
    }

    @Test
    void firstPlayerPastTwentyFourWinsImmediately() {
        GoosiState state = position(
                new int[]{0, 0, 0, 0, 0, 1, 2, 4, 0, 0, 0, 0}, 23, 18, 0);
        GoosiState after = sow(state, 5);

        assertThat(after.scores[0]).isEqualTo(26);
        assertThat(after.finished()).isTrue();
        assertThat(module.checkWinCondition(after)).isPresent();
    }

    @Test
    void visibleStateIncludesOnlyLegalHouseTaps() {
        GoosiState state = position(
                new int[]{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0}, 0, 0, 0);

        assertThat(module.visibleStateFor(state, state.players.get(0)).data())
                .containsEntry("legalPits", List.of(5))
                .containsEntry("pitsPerPlayer", 6);
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
}
