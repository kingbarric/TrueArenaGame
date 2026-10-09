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

class DraughtsUndoTest {
    private final DraughtsModule module = new DraughtsModule();

    private DraughtsState start() {
        return (DraughtsState) module.initialState(List.of("a", "b"), DraughtsConfig.defaults(), RandomSource.seeded(4));
    }

    private DraughtsState act(GameState s, String who, String type) {
        return (DraughtsState) module.onPlayerAction(s, PlayerAction.of(who, type, Map.of()));
    }

    private DraughtsState firstMove(DraughtsState s) {
        return (DraughtsState) module.onPlayerAction(s, PlayerAction.of(s.playerA, "MOVE",
                Map.of("from", Board.squareOf(3, 0), "to", Board.squareOf(4, 1))));
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> view(DraughtsState s) {
        return (Map<String, Object>) module.broadcastState(s).data();
    }

    @Test
    void theOtherPlayerSeesTheRequestAndAllowingItPutsTheBoardBack() {
        var start = start();
        var moved = firstMove(start);
        assertThat(view(moved)).containsEntry("undoableBy", start.playerA);

        var asked = act(moved, start.playerA, "REQUEST_UNDO");
        assertThat(view(asked)).containsEntry("pendingUndo", start.playerA).containsEntry("undoableBy", null);
        assertThat(asked.events().getLast().type()).isEqualTo("UNDO_REQUESTED");

        var undone = act(asked, start.playerB, "ACCEPT_UNDO");
        assertThat(undone.board).isEqualTo(start.board);
        assertThat(undone.phase()).isEqualTo("TurnA");
        assertThat(view(undone)).containsEntry("pendingUndo", null).containsEntry("undoableBy", null);
        // Only one step back.
        assertThatThrownBy(() -> act(undone, start.playerA, "REQUEST_UNDO"))
                .isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", "NOTHING_TO_UNDO");
    }

    @Test
    void sayingNoOrJustMovingKeepsTheMove() {
        var start = start();
        var asked = act(firstMove(start), start.playerA, "REQUEST_UNDO");
        var declined = act(asked, start.playerB, "DECLINE_UNDO");
        assertThat(declined.phase()).isEqualTo("TurnB");
        assertThat(declined.pendingUndo).isNull();
        assertThat(declined.events().getLast().type()).isEqualTo("UNDO_DECLINED");

        var askedAgain = act(firstMove(start), start.playerA, "REQUEST_UNDO");
        var replied = (DraughtsState) module.onPlayerAction(askedAgain, PlayerAction.of(start.playerB, "MOVE",
                Map.of("from", Board.squareOf(6, 1), "to", Board.squareOf(5, 0))));
        assertThat(replied.pendingUndo).isNull();
        assertThat(replied.phase()).isEqualTo("TurnA");
    }

    @Test
    void onlyTheMoverCanAskAndOnlyTheOtherPlayerCanAnswer() {
        var start = start();
        var moved = firstMove(start);
        assertThatThrownBy(() -> act(moved, start.playerB, "REQUEST_UNDO"))
                .isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", "NOTHING_TO_UNDO");
        var asked = act(moved, start.playerA, "REQUEST_UNDO");
        assertThatThrownBy(() -> act(asked, start.playerA, "ACCEPT_UNDO"))
                .isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", "NO_UNDO_REQUEST");
        assertThatThrownBy(() -> act(asked, start.playerA, "REQUEST_UNDO"))
                .isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", "UNDO_ALREADY_ASKED");
    }
}
