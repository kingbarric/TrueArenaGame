package app.truearena.game.draughts;

import app.truearena.engine.*;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class ScanMoveCodecTest {
    private final DraughtsModule game = new DraughtsModule();

    private DraughtsState chain(boolean mandatory) {
        var d = new DraughtsState.Draft();
        d.playerA = "a"; d.playerB = "b"; d.phase = "TurnA"; d.round = 1;
        d.config = new DraughtsConfig(60, mandatory);
        d.board[Board.squareOf(2, 1)] = Piece.A_MAN;
        d.board[Board.squareOf(3, 2)] = Piece.B_MAN;
        d.board[Board.squareOf(5, 4)] = Piece.B_MAN;
        d.requiredCaptureCount = mandatory ? CaptureEngine.requiredCaptureCount(d.board, "A") : 0;
        return d.build();
    }
    private PlayerAction move(int from, int to) { return PlayerAction.of("a", "MOVE", Map.of("from", from, "to", to)); }

    @Test void squareNumbersAndSideDirectionAgreeWithHub() {
        Piece[] board = new Piece[50];
        Arrays.fill(board, 0, 20, Piece.A_MAN); Arrays.fill(board, 30, 50, Piece.B_MAN);
        assertThat(ScanMoveCodec.position(board, "A")).isEqualTo("B" + "b".repeat(20) + "e".repeat(10) + "w".repeat(20));
        assertThat(ScanMoveCodec.resolve(board, "A", "20-25")).contains(List.of(new ScanMoveCodec.Move(19, 24)));
        assertThat(ScanMoveCodec.resolve(board, "B", "31-26")).contains(List.of(new ScanMoveCodec.Move(30, 25)));
        assertThat(ScanMoveCodec.resolve(board, "A", "1-50")).isEmpty();
        assertThat(ScanMoveCodec.resolve(board, "A", "20-25\nquit")).isEmpty();
    }

    @Test void reconstructsCapturedSquareNotationIntoCompleteCanonicalJumpSequence() {
        DraughtsState state = chain(true);
        int from = Board.squareOf(2, 1), pivot = Board.squareOf(4, 3), to = Board.squareOf(6, 5);
        int first = Board.squareOf(3, 2), second = Board.squareOf(5, 4);
        String hub = (from + 1) + "x" + (to + 1) + "x" + (second + 1) + "x" + (first + 1);
        var path = ScanMoveCodec.resolve(state.board, "A", hub).orElseThrow();
        assertThat(path).containsExactly(new ScanMoveCodec.Move(from, pivot), new ScanMoveCodec.Move(pivot, to));
        for (var step : path) state = (DraughtsState) game.onPlayerAction(state, move(step.from(), step.to()));
        assertThat(state.finished()).isTrue();
        assertThat(ScanMoveCodec.resolve(chain(true).board, "A", (from + 1) + "x" + (pivot + 1) + "x" + (first + 1))).isEmpty();
    }

    @Test void capturedPiecesBlockFlyingKingReversalsUntilTheWholeTurnFinishes() {
        Piece[] board = new Piece[50];
        int king = Board.squareOf(4, 5), first = Board.squareOf(3, 4), second = Board.squareOf(5, 6);
        board[king] = Piece.A_KING; board[first] = Piece.B_MAN; board[second] = Piece.B_MAN;
        assertThat(CaptureEngine.maxCaptureCount(board, king)).isEqualTo(1);
        int to = Board.squareOf(2, 3);
        Piece[] after = CaptureEngine.applyCapture(board, king, new CaptureEngine.Landing(first, to));
        assertThat(CaptureEngine.captureLandings(after, to)).isNotEmpty(); // already removed in display data
        assertThat(CaptureEngine.captureLandings(after, to, 1L << first)).isEmpty(); // still blocks this turn
        assertThat(ScanMoveCodec.resolve(board, "A", (king + 1) + "x" + (to + 1) + "x" + (first + 1))).isPresent();
    }

    @Test void snapshotPublishesBlockersAndRemainingCapturesAndOptionalChainsCannotStopWithAStep() {
        for (boolean mandatory : List.of(false, true)) {
            DraughtsState state = chain(mandatory);
            int from = Board.squareOf(2, 1), pivot = Board.squareOf(4, 3), to = Board.squareOf(6, 5);
            state = (DraughtsState) game.onPlayerAction(state, move(from, pivot));
            assertThat(state.activeSquare).isEqualTo(pivot);
            Map<String, Object> view = game.visibleStateFor(state, "a").data();
            assertThat(view.get("capturedSquares")).isEqualTo(List.of(Board.squareOf(3, 2)));
            assertThat(view.get("remainingCaptures")).isEqualTo(mandatory ? 1 : 0);
            DraughtsState midChain = state;
            assertThatThrownBy(() -> game.onPlayerAction(midChain, move(pivot, Board.squareOf(5, 2)))).isInstanceOf(RuleViolation.class);
            state = (DraughtsState) game.onPlayerAction(state, move(pivot, to));
            assertThat(state.capturedSquares).isZero();
            assertThat(state.activeSquare).isNull();
        }
    }
}
