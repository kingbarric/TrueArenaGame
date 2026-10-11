package app.truearena.game.draughts;

import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Seizure: miss an obvious capture and the opponent may take the piece that could have taken. */
class DraughtsSeizureTest {
    private final DraughtsModule module = new DraughtsModule();

    private static final int A_CAN_TAKE = Board.squareOf(4, 1);
    private static final int B_VICTIM = Board.squareOf(5, 2);
    private static final int A_ELSEWHERE = Board.squareOf(0, 1);
    private static final int B_ELSEWHERE = Board.squareOf(9, 0);

    /** A to move; A's man on (4,1) could jump B's man on (5,2) — but A may play elsewhere. */
    private DraughtsState position(DraughtsConfig config) {
        var start = (DraughtsState) module.initialState(List.of("a", "b"), config, RandomSource.seeded(4));
        var d = new DraughtsState.Draft(start);
        d.board = new Piece[Board.SIZE];
        d.board[A_CAN_TAKE] = Piece.A_MAN;
        d.board[A_ELSEWHERE] = Piece.A_MAN;
        d.board[B_VICTIM] = Piece.B_MAN;
        d.board[B_ELSEWHERE] = Piece.B_MAN;
        d.phase = "TurnA";
        d.requiredCaptureCount = 0;
        return d.build();
    }

    private DraughtsState act(GameState s, String who, String type, Map<String, Object> data) {
        return (DraughtsState) module.onPlayerAction(s, PlayerAction.of(who, type, data));
    }

    private DraughtsState missTheCapture(DraughtsState s) {
        return act(s, "a", "MOVE", Map.of("from", A_ELSEWHERE, "to", Board.squareOf(1, 0)));
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> view(DraughtsState s) {
        return (Map<String, Object>) module.broadcastState(s).data();
    }

    @Test
    void aMissedCaptureCanBeSeizedBeforeTheOpponentMoves() {
        var missed = missTheCapture(position(new DraughtsConfig(60, false, true)));
        assertThat(view(missed)).containsEntry("seizure", true)
                .containsEntry("seizable", List.of(A_CAN_TAKE)).containsEntry("seizableBy", "B");

        var seized = act(missed, "b", "SEIZE", Map.of("square", A_CAN_TAKE));
        assertThat(seized.board[A_CAN_TAKE]).isNull();
        assertThat(seized.events().getLast().type()).isEqualTo("PIECE_SEIZED");
        assertThat(seized.events().getLast().payload())
                .containsEntry("square", A_CAN_TAKE).containsEntry("side", "A").containsEntry("reason", "missed_capture");
        assertThat(seized.phase()).isEqualTo("TurnB"); // the seizure doesn't use up B's move
        assertThat(view(seized)).containsEntry("seizable", List.of()).containsEntry("seizableBy", null);
        assertThatThrownBy(() -> act(seized, "b", "SEIZE", Map.of("square", A_CAN_TAKE)))
                .isInstanceOf(RuleViolation.class);

        var moved = act(seized, "b", "MOVE", Map.of("from", B_VICTIM, "to", Board.squareOf(4, 3)));
        assertThat(moved.phase()).isEqualTo("TurnA");
    }

    @Test
    void movingInsteadOfSeizingLetsItGo() {
        var missed = missTheCapture(position(new DraughtsConfig(60, false, true)));
        var moved = act(missed, "b", "MOVE", Map.of("from", B_ELSEWHERE, "to", Board.squareOf(8, 1)));
        // B's chance is gone — and B's own man could have jumped A's, so now A may seize it.
        assertThat(view(moved)).containsEntry("seizable", List.of(B_VICTIM)).containsEntry("seizableBy", "A");
        assertThatThrownBy(() -> act(moved, "b", "SEIZE", Map.of("square", A_CAN_TAKE)))
                .isInstanceOf(RuleViolation.class);
    }

    @Test
    void takingTheCaptureOrMovingTheCapturerIsTrackedRight() {
        var config = new DraughtsConfig(60, false, true);
        var took = act(position(config), "a", "MOVE", Map.of("from", A_CAN_TAKE, "to", Board.squareOf(6, 3)));
        assertThat(view(took)).containsEntry("seizable", List.of());

        // The piece that could have taken stepped away instead: it's seizable where it now stands.
        var steppedAway = act(position(config), "a", "MOVE", Map.of("from", A_CAN_TAKE, "to", Board.squareOf(5, 0)));
        assertThat(view(steppedAway)).containsEntry("seizable", List.of(Board.squareOf(5, 0)));
    }

    @Test
    void onlyAPieceThatMissedCanBeSeizedAndOnlyWithSeizureOn() {
        var missed = missTheCapture(position(new DraughtsConfig(60, false, true)));
        assertThatThrownBy(() -> act(missed, "b", "SEIZE", Map.of("square", Board.squareOf(1, 0))))
                .isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", "NOT_SEIZABLE");
        assertThatThrownBy(() -> act(missed, "a", "SEIZE", Map.of("square", A_CAN_TAKE)))
                .isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", "NOT_YOUR_TURN");

        var casual = missTheCapture(position(DraughtsConfig.defaults()));
        assertThat(view(casual)).containsEntry("seizure", false).containsEntry("seizable", List.of());
        assertThat(new DraughtsConfig(60, true, true).seizure()).isFalse(); // forced captures can't be missed
    }

    @Test
    void theMoverCannotTakeBackTheirTurnOnceItWasSeized() {
        var missed = missTheCapture(position(new DraughtsConfig(60, false, true)));
        var seized = act(missed, "b", "SEIZE", Map.of("square", A_CAN_TAKE));
        assertThatThrownBy(() -> act(seized, "a", "REQUEST_UNDO", Map.of()))
                .isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", "TOO_LATE_TO_UNDO");
    }
}
