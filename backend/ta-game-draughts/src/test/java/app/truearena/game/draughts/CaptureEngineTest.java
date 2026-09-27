package app.truearena.game.draughts;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The rules engine in isolation — no state, no events, just board arrays.
 * One scenario per test so a failure points at the exact rule that broke.
 * Every square used here has an odd (row + col) — the only playable ones;
 * a diagonal step always preserves that parity, so picking one valid start
 * square keeps every destination on the board valid too.
 */
class CaptureEngineTest {

    // ---------------------------------------------------------------- coordinates

    @Test
    void squareAndRowColRoundTrip() {
        for (int row = 0; row < 10; row++) {
            for (int col = 0; col < 10; col++) {
                if (!Board.isPlayable(row, col)) continue;
                int sq = Board.squareOf(row, col);
                assertThat(Board.rowOf(sq)).isEqualTo(row);
                assertThat(Board.colOf(sq)).isEqualTo(col);
            }
        }
    }

    @Test
    void exactlyFiftyPlayableSquares() {
        int count = 0;
        for (int row = 0; row < 10; row++) {
            for (int col = 0; col < 10; col++) {
                if (Board.isPlayable(row, col)) count++;
            }
        }
        assertThat(count).isEqualTo(50);
    }

    // ---------------------------------------------------------------- simple moves

    @Test
    void manMovesOnlyForwardDiagonally() {
        Piece[] board = new Piece[Board.SIZE];
        int start = Board.squareOf(4, 3);
        board[start] = Piece.A_MAN; // A moves toward row 9 (increasing)
        List<Integer> dest = CaptureEngine.simpleLandings(board, start);
        assertThat(dest).containsExactlyInAnyOrder(Board.squareOf(5, 2), Board.squareOf(5, 4));
    }

    @Test
    void manCannotStepBackward() {
        Piece[] board = new Piece[Board.SIZE];
        int start = Board.squareOf(4, 3);
        board[start] = Piece.B_MAN; // B moves toward row 0 (decreasing)
        List<Integer> dest = CaptureEngine.simpleLandings(board, start);
        assertThat(dest).containsExactlyInAnyOrder(Board.squareOf(3, 2), Board.squareOf(3, 4));
    }

    @Test
    void kingMovesAnyDistanceUntilBlocked() {
        Piece[] board = new Piece[Board.SIZE];
        int start = Board.squareOf(4, 3);
        board[start] = Piece.A_KING;
        List<Integer> dest = CaptureEngine.simpleLandings(board, start);
        assertThat(dest).contains(Board.squareOf(5, 4), Board.squareOf(9, 8), Board.squareOf(1, 0));
        assertThat(dest).hasSize(15); // 3 + 4 + 3 + 5 squares across the four rays from (4,3)
    }

    @Test
    void kingStopsBeforeAnyPiece() {
        Piece[] board = new Piece[Board.SIZE];
        int start = Board.squareOf(4, 3);
        board[start] = Piece.A_KING;
        board[Board.squareOf(7, 6)] = Piece.B_MAN; // blocks the (5,4)(6,5)(7,6)... ray
        List<Integer> dest = CaptureEngine.simpleLandings(board, start);
        assertThat(dest).contains(Board.squareOf(5, 4), Board.squareOf(6, 5));
        assertThat(dest).doesNotContain(Board.squareOf(7, 6), Board.squareOf(8, 7));
    }

    // ---------------------------------------------------------------- captures

    @Test
    void manCapturesForward() {
        Piece[] board = new Piece[Board.SIZE];
        int from = Board.squareOf(3, 4);
        board[from] = Piece.A_MAN;
        board[Board.squareOf(4, 5)] = Piece.B_MAN;
        List<CaptureEngine.Landing> landings = CaptureEngine.captureLandings(board, from);
        assertThat(landings).containsExactly(new CaptureEngine.Landing(Board.squareOf(4, 5), Board.squareOf(5, 6)));
    }

    @Test
    void manCapturesBackwardToo() {
        // International rules: a man can only *step* forward, but can *capture* in any direction.
        Piece[] board = new Piece[Board.SIZE];
        int from = Board.squareOf(4, 3);
        board[from] = Piece.A_MAN;
        board[Board.squareOf(3, 2)] = Piece.B_MAN; // behind A's forward direction
        List<CaptureEngine.Landing> landings = CaptureEngine.captureLandings(board, from);
        assertThat(landings).containsExactly(new CaptureEngine.Landing(Board.squareOf(3, 2), Board.squareOf(2, 1)));
    }

    @Test
    void manCannotCaptureOwnPiece() {
        Piece[] board = new Piece[Board.SIZE];
        int from = Board.squareOf(3, 4);
        board[from] = Piece.A_MAN;
        board[Board.squareOf(4, 5)] = Piece.A_MAN;
        assertThat(CaptureEngine.captureLandings(board, from)).isEmpty();
    }

    @Test
    void manCannotJumpIfLandingIsBlocked() {
        Piece[] board = new Piece[Board.SIZE];
        int from = Board.squareOf(3, 4);
        board[from] = Piece.A_MAN;
        board[Board.squareOf(4, 5)] = Piece.B_MAN;
        board[Board.squareOf(5, 6)] = Piece.B_MAN; // landing square occupied
        assertThat(CaptureEngine.captureLandings(board, from)).isEmpty();
    }

    @Test
    void kingFliesToCaptureWithMultipleLandingChoices() {
        Piece[] board = new Piece[Board.SIZE];
        int from = Board.squareOf(1, 0);
        board[from] = Piece.A_KING;
        board[Board.squareOf(4, 3)] = Piece.B_MAN;
        // empty at (5,4) (6,5) (7,6) (8,7) (9,8) beyond the captured piece
        List<CaptureEngine.Landing> landings = CaptureEngine.captureLandings(board, from);
        assertThat(landings).hasSize(5);
        assertThat(landings).allMatch(l -> l.captured() == Board.squareOf(4, 3));
    }

    @Test
    void kingCannotFlyPastTwoPiecesInARow() {
        Piece[] board = new Piece[Board.SIZE];
        int from = Board.squareOf(0, 1);
        board[from] = Piece.A_KING;
        board[Board.squareOf(3, 4)] = Piece.B_MAN;
        board[Board.squareOf(5, 6)] = Piece.B_MAN; // a second enemy piece past the first, beyond empty (4,5)
        List<CaptureEngine.Landing> landings = CaptureEngine.captureLandings(board, from);
        // can capture the first piece landing only on the single empty square before the second piece
        assertThat(landings).containsExactly(new CaptureEngine.Landing(Board.squareOf(3, 4), Board.squareOf(4, 5)));
    }

    // ---------------------------------------------------------------- mandatory maximum capture

    @Test
    void noCaptureAvailableMeansRequiredCountIsZero() {
        Piece[] board = new Piece[Board.SIZE];
        board[Board.squareOf(3, 4)] = Piece.A_MAN;
        assertThat(CaptureEngine.requiredCaptureCount(board, DraughtsState.SIDE_A)).isZero();
    }

    @Test
    void singleCaptureAvailableGivesRequiredCountOne() {
        Piece[] board = new Piece[Board.SIZE];
        board[Board.squareOf(3, 4)] = Piece.A_MAN;
        board[Board.squareOf(4, 5)] = Piece.B_MAN;
        assertThat(CaptureEngine.requiredCaptureCount(board, DraughtsState.SIDE_A)).isEqualTo(1);
    }

    @Test
    void multiJumpChainCountsEveryCapture() {
        Piece[] board = new Piece[Board.SIZE];
        int from = Board.squareOf(1, 0);
        board[from] = Piece.A_MAN;
        board[Board.squareOf(2, 1)] = Piece.B_MAN; // first jump lands on (3,2)
        board[Board.squareOf(4, 3)] = Piece.B_MAN; // second jump lands on (5,4)
        assertThat(CaptureEngine.maxCaptureCount(board, from)).isEqualTo(2);
        assertThat(CaptureEngine.requiredCaptureCount(board, DraughtsState.SIDE_A)).isEqualTo(2);
    }

    @Test
    void mustTakeTheGlobalMaximumAcrossAllPieces() {
        Piece[] board = new Piece[Board.SIZE];
        // Piece 1 (at 1,0) can only capture once.
        board[Board.squareOf(1, 0)] = Piece.A_MAN;
        board[Board.squareOf(2, 1)] = Piece.B_MAN;
        // Piece 2 (at 1,4) can chain two captures the other way.
        board[Board.squareOf(1, 4)] = Piece.A_MAN;
        board[Board.squareOf(2, 5)] = Piece.B_MAN;
        board[Board.squareOf(4, 7)] = Piece.B_MAN;
        assertThat(CaptureEngine.requiredCaptureCount(board, DraughtsState.SIDE_A)).isEqualTo(2);
    }

    @Test
    void hasAnyLegalMoveIsFalseWhenCompletelyBlocked() {
        Piece[] board = new Piece[Board.SIZE];
        int from = Board.squareOf(8, 1);
        board[from] = Piece.A_MAN;
        board[Board.squareOf(9, 0)] = Piece.A_MAN;
        board[Board.squareOf(9, 2)] = Piece.A_MAN;
        assertThat(CaptureEngine.hasAnyLegalMove(board, DraughtsState.SIDE_A)).isFalse();
    }

    @Test
    void hasAnyLegalMoveIsFalseWithNoPiecesAtAll() {
        Piece[] board = new Piece[Board.SIZE];
        assertThat(CaptureEngine.hasAnyLegalMove(board, DraughtsState.SIDE_A)).isFalse();
    }
}
