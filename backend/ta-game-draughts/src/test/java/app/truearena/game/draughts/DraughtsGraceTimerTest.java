package app.truearena.game.draughts;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.Phase;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The grace ladder that replaced "your clock ran out, you lose".
 *
 * <p>Someone who puts their phone down mid-game gets two paused chances to
 * come back before the turn is forfeit — see
 * {@link DraughtsModule#onPhaseElapsed}.
 */
class DraughtsGraceTimerTest {

    private final DraughtsModule module = new DraughtsModule();
    private static final String P1 = "p1";
    private static final String P2 = "p2";

    private DraughtsState stateIn(String phase) {
        DraughtsState.Draft d = new DraughtsState.Draft();
        d.config = DraughtsConfig.defaults();
        d.playerA = P1;
        d.playerB = P2;
        // A lone man each, so neither side is stalemated into a win.
        d.board[22] = Piece.A_MAN;
        d.board[27] = Piece.B_MAN;
        d.phase = phase;
        d.round = 1;
        return d.build();
    }

    private String phaseAfterElapsing(String phase) {
        return module.onPhaseElapsed(stateIn(phase), phase).phase();
    }

    @Test
    void everyGracePhaseWaitsPausedForAPlayerToResume() {
        List<Phase> phases = module.definePhases(DraughtsConfig.defaults());
        List<Phase> grace = phases.stream().filter(p -> p.name().startsWith("Grace")).toList();

        assertThat(grace).hasSize(4); // two chances, each side
        assertThat(grace).allSatisfy(p -> {
            // The whole point: the clock must not drain while the player is
            // still away, so entering the phase suspends the room.
            assertThat(p.startsPaused()).as("%s starts paused", p.name()).isTrue();
            assertThat(p.timed()).as("%s is timed", p.name()).isTrue();
        });
    }

    @Test
    void aTurnRunningOutPausesInsteadOfEndingTheGame() {
        GameState after = module.onPhaseElapsed(stateIn("TurnA"), "TurnA");

        assertThat(after.finished()).as("the game must not end on the first timeout").isFalse();
        assertThat(after.phase()).isEqualTo("GraceA1");
        assertThat(module.checkWinCondition(after)).isEmpty();
    }

    @Test
    void theFirstChanceIsTwentySecondsAndIsNotTheLastOne() {
        GameState after = module.onPhaseElapsed(stateIn("TurnB"), "TurnB");
        GameEvent grace = lastEvent(after);

        assertThat(grace.type()).isEqualTo("TURN_GRACE");
        assertThat(grace.payload()).containsEntry("side", "B");
        assertThat(grace.payload()).containsEntry("seconds", DraughtsModule.GRACE_SECONDS);
        assertThat(grace.payload()).containsEntry("lastChance", false);
    }

    @Test
    void theSecondChanceIsFiveSecondsAndIsFlaggedAsTheLastOne() {
        GameState after = module.onPhaseElapsed(stateIn("GraceA1"), "GraceA1");
        GameEvent grace = lastEvent(after);

        assertThat(after.phase()).isEqualTo("GraceA2");
        assertThat(after.finished()).isFalse();
        assertThat(grace.payload()).containsEntry("seconds", DraughtsModule.FINAL_GRACE_SECONDS);
        // This is what tells the client to warn before resuming.
        assertThat(grace.payload()).containsEntry("lastChance", true);
    }

    @Test
    void onlyTheFinalChaneRunningOutLosesTheGame() {
        GameState after = module.onPhaseElapsed(stateIn("GraceA2"), "GraceA2");

        assertThat(after.finished()).isTrue();
        assertThat(module.checkWinCondition(after))
                .get()
                .extracting(w -> w.perPlayerOutcome().get(P2))
                .isEqualTo("won"); // A was on the clock, so B takes it
    }

    @Test
    void theLadderRunsIndependentlyForEachSide() {
        assertThat(phaseAfterElapsing("TurnA")).isEqualTo("GraceA1");
        assertThat(phaseAfterElapsing("TurnB")).isEqualTo("GraceB1");
        assertThat(phaseAfterElapsing("GraceA1")).isEqualTo("GraceA2");
        assertThat(phaseAfterElapsing("GraceB1")).isEqualTo("GraceB2");

        GameState bOutOfChances = module.onPhaseElapsed(stateIn("GraceB2"), "GraceB2");
        assertThat(module.checkWinCondition(bOutOfChances))
                .get()
                .extracting(w -> w.perPlayerOutcome().get(P1))
                .isEqualTo("won");
    }

    @Test
    void theSideOnTheClockStillOwnsTheTurnThroughoutTheGrace() {
        // They must be able to actually play during the chance they were
        // given — a grace they can't move in would be pointless.
        assertThat(stateIn("GraceA1").turnSide()).isEqualTo(DraughtsState.SIDE_A);
        assertThat(stateIn("GraceA2").turnSide()).isEqualTo(DraughtsState.SIDE_A);
        assertThat(stateIn("GraceB1").turnSide()).isEqualTo(DraughtsState.SIDE_B);
        assertThat(stateIn("GraceB2").turnSide()).isEqualTo(DraughtsState.SIDE_B);
    }

    private GameEvent lastEvent(GameState state) {
        List<GameEvent> events = state.events();
        assertThat(events).isNotEmpty();
        return events.get(events.size() - 1);
    }

    @Test
    void aFinishedGameIgnoresAStrayTimer() {
        DraughtsState.Draft d = new DraughtsState.Draft(stateIn("TurnA"));
        d.phase = "Results";
        GameState finished = d.build();

        assertThat(module.onPhaseElapsed(finished, "TurnA")).isSameAs(finished);
        assertThat(finished.events()).noneSatisfy(e -> assertThat(e.type()).isEqualTo("TURN_GRACE"));
    }

    @Test
    void graceEventsCarryNoHiddenInformation() {
        GameState after = module.onPhaseElapsed(stateIn("TurnA"), "TurnA");
        Map<String, Object> payload = lastEvent(after).payload();
        assertThat(payload).containsOnlyKeys("side", "seconds", "lastChance");
    }
}
