package app.truearena.game.draughts;

import java.util.ArrayList;
import java.util.List;

/**
 * The rules engine, as pure functions over a {@code Piece[50]} board —
 * nothing here touches {@link DraughtsState} or events, so it's exhaustively
 * unit-testable on its own. Implements the two things that make
 * international draughts more than checkers:
 *
 * <ul>
 *   <li><b>Flying kings</b>: a king moves/captures any distance along an
 *   empty diagonal, not just one square (see {@link #captureLandings} and
 *   {@link #simpleLandings}).
 *   <li><b>Mandatory maximum capture</b>: if any capture is available for a
 *   side, one must be taken, and it must belong to a sequence capturing the
 *   most pieces achievable this turn — see {@link #requiredCaptureCount} and
 *   {@link #maxCaptureCount}, which {@link DraughtsModule} uses to validate
 *   each step of a multi-jump chain, not just whether a jump is *possible*.
 * </ul>
 */
public final class CaptureEngine {

    private CaptureEngine() {
    }

    /** One jump's outcome: the square captured, and where the jumping piece lands. */
    public record Landing(int captured, int to) {
    }

    /** Every single-jump capture available from `from` on the current board. */
    public static List<Landing> captureLandings(Piece[] board, int from) {
        Piece piece = board[from];
        List<Landing> out = new ArrayList<>();
        if (piece == null) {
            return out;
        }
        for (int[] dir : Board.DIRECTIONS) {
            if (piece.isKing()) {
                addKingCaptureLandings(board, from, dir, piece.side(), out);
            } else {
                addManCaptureLanding(board, from, dir, piece.side(), out);
            }
        }
        return out;
    }

    private static void addManCaptureLanding(Piece[] board, int from, int[] dir, String side, List<Landing> out) {
        int adjacent = Board.step(from, dir[0], dir[1]);
        if (adjacent < 0 || board[adjacent] == null || board[adjacent].side().equals(side)) {
            return;
        }
        int landing = Board.step(adjacent, dir[0], dir[1]);
        if (landing >= 0 && board[landing] == null) {
            out.add(new Landing(adjacent, landing));
        }
    }

    private static void addKingCaptureLandings(Piece[] board, int from, int[] dir, String side, List<Landing> out) {
        int cur = from;
        while (true) {
            cur = Board.step(cur, dir[0], dir[1]);
            if (cur < 0 || board[cur] != null) {
                break; // off board, or the first occupied square in this direction
            }
        }
        if (cur < 0 || board[cur].side().equals(side)) {
            return; // ran off the edge, or the blocker is our own piece — no capture this way
        }
        int captured = cur;
        // every empty square beyond the captured piece is a legal landing spot
        int landing = Board.step(captured, dir[0], dir[1]);
        while (landing >= 0 && board[landing] == null) {
            out.add(new Landing(captured, landing));
            landing = Board.step(landing, dir[0], dir[1]);
        }
    }

    /** Every non-capturing destination available from `from` on the current board. */
    public static List<Integer> simpleLandings(Piece[] board, int from) {
        Piece piece = board[from];
        List<Integer> out = new ArrayList<>();
        if (piece == null) {
            return out;
        }
        for (int[] dir : Board.DIRECTIONS) {
            if (!piece.isKing() && !isForward(piece, dir[0])) {
                continue; // a man only ever steps forward (it can still *capture* backward)
            }
            if (piece.isKing()) {
                int cur = from;
                while (true) {
                    cur = Board.step(cur, dir[0], dir[1]);
                    if (cur < 0 || board[cur] != null) {
                        break;
                    }
                    out.add(cur);
                }
            } else {
                int to = Board.step(from, dir[0], dir[1]);
                if (to >= 0 && board[to] == null) {
                    out.add(to);
                }
            }
        }
        return out;
    }

    private static boolean isForward(Piece piece, int dRow) {
        return piece.side().equals(DraughtsState.SIDE_A) ? dRow > 0 : dRow < 0;
    }

    /** Max total pieces capturable in one turn if this chain starts at `from`. 0 if none. */
    public static int maxCaptureCount(Piece[] board, int from) {
        int best = 0;
        for (Landing landing : captureLandings(board, from)) {
            Piece[] after = applyCapture(board, from, landing);
            best = Math.max(best, 1 + maxCaptureCount(after, landing.to()));
        }
        return best;
    }

    /** The board-wide max capture count for `side` this turn — 0 means no capture is available. */
    public static int requiredCaptureCount(Piece[] board, String side) {
        int best = 0;
        for (int sq = 0; sq < Board.SIZE; sq++) {
            if (board[sq] != null && board[sq].side().equals(side)) {
                best = Math.max(best, maxCaptureCount(board, sq));
            }
        }
        return best;
    }

    /** Whether `side` has anything at all to play — a capture or a simple move. */
    public static boolean hasAnyLegalMove(Piece[] board, String side) {
        if (requiredCaptureCount(board, side) > 0) {
            return true;
        }
        for (int sq = 0; sq < Board.SIZE; sq++) {
            if (board[sq] != null && board[sq].side().equals(side) && !simpleLandings(board, sq).isEmpty()) {
                return true;
            }
        }
        return false;
    }

    public static Piece[] applyCapture(Piece[] board, int from, Landing landing) {
        Piece[] copy = board.clone();
        copy[landing.to()] = copy[from];
        copy[from] = null;
        copy[landing.captured()] = null;
        return copy;
    }

    public static Piece[] applySimpleMove(Piece[] board, int from, int to) {
        Piece[] copy = board.clone();
        copy[to] = copy[from];
        copy[from] = null;
        return copy;
    }
}
