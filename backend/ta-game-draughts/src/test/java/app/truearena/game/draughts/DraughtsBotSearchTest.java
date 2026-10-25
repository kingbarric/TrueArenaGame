package app.truearena.game.draughts;

import app.truearena.engine.PlayerAction;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class DraughtsBotSearchTest {
    @Test void continuingCaptureUsesTheLockedPieceEvenWhenAnotherPieceCanCapture() {
        DraughtsState.Draft d = new DraughtsState.Draft();
        d.playerA = "a"; d.playerB = "b"; d.phase = "TurnA"; d.round = 1;
        d.config = new DraughtsConfig(60, false);
        int from = Board.squareOf(3, 2), captured = Board.squareOf(4, 3), to = Board.squareOf(5, 4);
        d.board[from] = Piece.A_MAN;
        d.board[captured] = Piece.B_MAN;
        d.board[Board.squareOf(3, 6)] = Piece.A_MAN;
        d.board[Board.squareOf(4, 7)] = Piece.B_MAN;
        d.activeSquare = from;
        PlayerAction action = DraughtsBotSearch.choose(d.board, "a", "b", "a", from, false, 3, 100).orElseThrow();
        assertThat(action.data()).containsEntry("from", from).containsEntry("to", to);
        new DraughtsModule().onPlayerAction(d.build(), action); // authoritative chain constraint
    }

    @Test void mandatoryCaptureChoosesTheLongestChain() {
        DraughtsState.Draft d = new DraughtsState.Draft();
        d.playerA = "a"; d.playerB = "b"; d.phase = "TurnA"; d.round = 1;
        d.config = new DraughtsConfig(60, true);
        int from = Board.squareOf(1, 0);
        d.board[from] = Piece.A_MAN;
        d.board[Board.squareOf(2, 1)] = Piece.B_MAN;
        d.board[Board.squareOf(4, 3)] = Piece.B_MAN;
        d.board[Board.squareOf(1, 6)] = Piece.A_MAN;
        d.board[Board.squareOf(2, 7)] = Piece.B_MAN;
        d.requiredCaptureCount = 2;
        PlayerAction action = DraughtsBotSearch.choose(d.board, "a", "b", "a", null, true, 3, 100).orElseThrow();
        assertThat(action.data()).containsEntry("from", from);
        new DraughtsModule().onPlayerAction(d.build(), action);
    }
}
