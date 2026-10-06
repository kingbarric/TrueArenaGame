package app.truearena.game.chess;

import java.util.ArrayList;
import java.util.List;

/**
 * An immutable chess position: placement, side to move, castling rights, en
 * passant target and the move counters — exactly the six fields of a FEN.
 * Everything rules-related lives here: move generation, the legality filter
 * (a move may never leave its own king attacked, which is what makes pins,
 * en passant discoveries and "castling out of check" fall out naturally), and
 * the draw-relevant facts the game layer needs (repetition identity, dead
 * positions).
 */
public final class Position {

    public static final String START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

    public static final int WHITE_KINGSIDE = 1;
    public static final int WHITE_QUEENSIDE = 2;
    public static final int BLACK_KINGSIDE = 4;
    public static final int BLACK_QUEENSIDE = 8;

    private static final int[][] KNIGHT_STEPS = {{1, 2}, {2, 1}, {2, -1}, {1, -2}, {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}};
    private static final int[][] KING_STEPS = {{1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}};
    private static final int[][] DIAGONALS = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}};
    private static final int[][] ORTHOGONALS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
    private static final PieceKind[] PROMOTIONS = {PieceKind.QUEEN, PieceKind.ROOK, PieceKind.BISHOP, PieceKind.KNIGHT};

    private final Piece[] board;
    private final Color sideToMove;
    private final int castling;
    private final int epSquare;
    private final int halfmoveClock;
    private final int fullmoveNumber;

    private Position(Piece[] board, Color sideToMove, int castling, int epSquare, int halfmoveClock, int fullmoveNumber) {
        this.board = board;
        this.sideToMove = sideToMove;
        this.castling = castling;
        this.epSquare = epSquare;
        this.halfmoveClock = halfmoveClock;
        this.fullmoveNumber = fullmoveNumber;
    }

    public static Position initial() {
        return fromFen(START_FEN);
    }

    // ---------------------------------------------------------------- FEN

    public static Position fromFen(String fen) {
        String[] parts = fen.trim().split("\\s+");
        if (parts.length < 4) {
            throw new IllegalArgumentException("FEN needs at least placement, side, castling and en passant: " + fen);
        }
        String[] rows = parts[0].split("/");
        if (rows.length != 8) {
            throw new IllegalArgumentException("FEN placement needs 8 ranks: " + fen);
        }
        Piece[] board = new Piece[64];
        for (int i = 0; i < 8; i++) {
            int rank = 7 - i;
            int file = 0;
            for (char c : rows[i].toCharArray()) {
                if (Character.isDigit(c)) {
                    file += c - '0';
                } else {
                    Piece p = Piece.fromFen(c);
                    if (p == null || file > 7) {
                        throw new IllegalArgumentException("bad FEN rank '" + rows[i] + "'");
                    }
                    board[Square.of(file, rank)] = p;
                    file++;
                }
            }
            if (file != 8) {
                throw new IllegalArgumentException("FEN rank '" + rows[i] + "' doesn't cover 8 files");
            }
        }
        Color side = switch (parts[1]) {
            case "w" -> Color.WHITE;
            case "b" -> Color.BLACK;
            default -> throw new IllegalArgumentException("bad side to move: " + parts[1]);
        };
        int castling = 0;
        if (!"-".equals(parts[2])) {
            for (char c : parts[2].toCharArray()) {
                castling |= switch (c) {
                    case 'K' -> WHITE_KINGSIDE;
                    case 'Q' -> WHITE_QUEENSIDE;
                    case 'k' -> BLACK_KINGSIDE;
                    case 'q' -> BLACK_QUEENSIDE;
                    default -> throw new IllegalArgumentException("bad castling field: " + parts[2]);
                };
            }
        }
        int ep = "-".equals(parts[3]) ? Square.NONE : Square.parse(parts[3]);
        if (!"-".equals(parts[3]) && ep == Square.NONE) {
            throw new IllegalArgumentException("bad en passant square: " + parts[3]);
        }
        int half = parts.length > 4 ? Integer.parseInt(parts[4]) : 0;
        int full = parts.length > 5 ? Integer.parseInt(parts[5]) : 1;

        int whiteKings = 0;
        int blackKings = 0;
        for (Piece p : board) {
            if (p == Piece.WHITE_KING) whiteKings++;
            if (p == Piece.BLACK_KING) blackKings++;
        }
        if (whiteKings != 1 || blackKings != 1) {
            throw new IllegalArgumentException("each side needs exactly one king");
        }
        Position pos = new Position(board, side, castling & supportedCastling(board), ep, half, full);
        if (pos.isAttacked(pos.kingSquare(side.opposite()), side)) {
            throw new IllegalArgumentException("the side not to move is in check");
        }
        return pos;
    }

    /** Rights only make sense while king and rook still stand on their original squares. */
    private static int supportedCastling(Piece[] board) {
        int rights = 0;
        if (board[4] == Piece.WHITE_KING) {
            if (board[7] == Piece.WHITE_ROOK) rights |= WHITE_KINGSIDE;
            if (board[0] == Piece.WHITE_ROOK) rights |= WHITE_QUEENSIDE;
        }
        if (board[60] == Piece.BLACK_KING) {
            if (board[63] == Piece.BLACK_ROOK) rights |= BLACK_KINGSIDE;
            if (board[56] == Piece.BLACK_ROOK) rights |= BLACK_QUEENSIDE;
        }
        return rights;
    }

    public String fen() {
        return placementFen() + " " + (sideToMove == Color.WHITE ? "w" : "b") + " " + castlingFen() + " "
                + (epSquare == Square.NONE ? "-" : Square.name(epSquare)) + " " + halfmoveClock + " " + fullmoveNumber;
    }

    private String placementFen() {
        StringBuilder sb = new StringBuilder();
        for (int rank = 7; rank >= 0; rank--) {
            int empty = 0;
            for (int file = 0; file < 8; file++) {
                Piece p = board[Square.of(file, rank)];
                if (p == null) {
                    empty++;
                } else {
                    if (empty > 0) {
                        sb.append(empty);
                        empty = 0;
                    }
                    sb.append(p.fen());
                }
            }
            if (empty > 0) sb.append(empty);
            if (rank > 0) sb.append('/');
        }
        return sb.toString();
    }

    private String castlingFen() {
        StringBuilder sb = new StringBuilder();
        if ((castling & WHITE_KINGSIDE) != 0) sb.append('K');
        if ((castling & WHITE_QUEENSIDE) != 0) sb.append('Q');
        if ((castling & BLACK_KINGSIDE) != 0) sb.append('k');
        if ((castling & BLACK_QUEENSIDE) != 0) sb.append('q');
        return sb.isEmpty() ? "-" : sb.toString();
    }

    // ---------------------------------------------------------------- accessors

    public Piece at(int sq) {
        return board[sq];
    }

    public Color sideToMove() {
        return sideToMove;
    }

    public int castlingRights() {
        return castling;
    }

    public int epSquare() {
        return epSquare;
    }

    public int halfmoveClock() {
        return halfmoveClock;
    }

    public int fullmoveNumber() {
        return fullmoveNumber;
    }

    public int kingSquare(Color color) {
        Piece king = Piece.of(color, PieceKind.KING);
        for (int sq = 0; sq < 64; sq++) {
            if (board[sq] == king) {
                return sq;
            }
        }
        throw new IllegalStateException(color + " has no king");
    }

    public boolean inCheck() {
        return isAttacked(kingSquare(sideToMove), sideToMove.opposite());
    }

    // ---------------------------------------------------------------- attacks

    /** Whether any piece of {@code by} attacks {@code sq} (regardless of whose move it is). */
    public boolean isAttacked(int sq, Color by) {
        int f = Square.file(sq);
        int r = Square.rank(sq);

        int pawnRank = by == Color.WHITE ? r - 1 : r + 1;
        Piece pawn = Piece.of(by, PieceKind.PAWN);
        for (int df : new int[]{-1, 1}) {
            if (Square.onBoard(f + df, pawnRank) && board[Square.of(f + df, pawnRank)] == pawn) {
                return true;
            }
        }
        if (stepAttack(f, r, KNIGHT_STEPS, Piece.of(by, PieceKind.KNIGHT))
                || stepAttack(f, r, KING_STEPS, Piece.of(by, PieceKind.KING))) {
            return true;
        }
        return rayAttack(f, r, DIAGONALS, Piece.of(by, PieceKind.BISHOP), Piece.of(by, PieceKind.QUEEN))
                || rayAttack(f, r, ORTHOGONALS, Piece.of(by, PieceKind.ROOK), Piece.of(by, PieceKind.QUEEN));
    }

    private boolean stepAttack(int f, int r, int[][] steps, Piece attacker) {
        for (int[] s : steps) {
            int nf = f + s[0];
            int nr = r + s[1];
            if (Square.onBoard(nf, nr) && board[Square.of(nf, nr)] == attacker) {
                return true;
            }
        }
        return false;
    }

    private boolean rayAttack(int f, int r, int[][] dirs, Piece slider, Piece queen) {
        for (int[] d : dirs) {
            int nf = f + d[0];
            int nr = r + d[1];
            while (Square.onBoard(nf, nr)) {
                Piece p = board[Square.of(nf, nr)];
                if (p != null) {
                    if (p == slider || p == queen) {
                        return true;
                    }
                    break;
                }
                nf += d[0];
                nr += d[1];
            }
        }
        return false;
    }

    // ---------------------------------------------------------------- moves

    /** Every legal move for the side to move. */
    public List<Move> legalMoves() {
        List<Move> legal = new ArrayList<>();
        for (Move m : pseudoLegalMoves()) {
            if (isLegal(m)) {
                legal.add(m);
            }
        }
        return legal;
    }

    public List<Move> legalMovesFrom(int from) {
        return legalMoves().stream().filter(m -> m.from() == from).toList();
    }

    /** A pseudo-legal move is legal iff it doesn't leave the mover's own king attacked. */
    private boolean isLegal(Move m) {
        Position next = play(m);
        return !next.isAttacked(next.kingSquare(sideToMove), sideToMove.opposite());
    }

    private List<Move> pseudoLegalMoves() {
        List<Move> out = new ArrayList<>();
        for (int sq = 0; sq < 64; sq++) {
            Piece p = board[sq];
            if (p == null || p.color() != sideToMove) {
                continue;
            }
            switch (p.kind()) {
                case PAWN -> pawnMoves(sq, out);
                case KNIGHT -> stepMoves(sq, KNIGHT_STEPS, out);
                case BISHOP -> slideMoves(sq, DIAGONALS, out);
                case ROOK -> slideMoves(sq, ORTHOGONALS, out);
                case QUEEN -> {
                    slideMoves(sq, DIAGONALS, out);
                    slideMoves(sq, ORTHOGONALS, out);
                }
                case KING -> {
                    stepMoves(sq, KING_STEPS, out);
                    castlingMoves(out);
                }
            }
        }
        return out;
    }

    private void pawnMoves(int sq, List<Move> out) {
        int f = Square.file(sq);
        int r = Square.rank(sq);
        int forward = sideToMove == Color.WHITE ? 1 : -1;
        int startRank = sideToMove == Color.WHITE ? 1 : 6;
        int lastRank = sideToMove == Color.WHITE ? 7 : 0;

        int oneRank = r + forward;
        if (Square.onBoard(f, oneRank) && board[Square.of(f, oneRank)] == null) {
            addPawnMove(sq, Square.of(f, oneRank), oneRank == lastRank, out);
            int twoRank = r + 2 * forward;
            if (r == startRank && board[Square.of(f, twoRank)] == null) {
                out.add(new Move(sq, Square.of(f, twoRank), null, Move.Flag.DOUBLE_PUSH));
            }
        }
        for (int df : new int[]{-1, 1}) {
            if (!Square.onBoard(f + df, oneRank)) {
                continue;
            }
            int target = Square.of(f + df, oneRank);
            Piece victim = board[target];
            if (victim != null && victim.color() != sideToMove) {
                addPawnMove(sq, target, oneRank == lastRank, out);
            } else if (target == epSquare) {
                out.add(new Move(sq, target, null, Move.Flag.EN_PASSANT));
            }
        }
    }

    private static void addPawnMove(int from, int to, boolean promotes, List<Move> out) {
        if (promotes) {
            for (PieceKind kind : PROMOTIONS) {
                out.add(new Move(from, to, kind, Move.Flag.NORMAL));
            }
        } else {
            out.add(new Move(from, to, null, Move.Flag.NORMAL));
        }
    }

    private void stepMoves(int sq, int[][] steps, List<Move> out) {
        int f = Square.file(sq);
        int r = Square.rank(sq);
        for (int[] s : steps) {
            int nf = f + s[0];
            int nr = r + s[1];
            if (!Square.onBoard(nf, nr)) {
                continue;
            }
            Piece target = board[Square.of(nf, nr)];
            if (target == null || target.color() != sideToMove) {
                out.add(new Move(sq, Square.of(nf, nr), null, Move.Flag.NORMAL));
            }
        }
    }

    private void slideMoves(int sq, int[][] dirs, List<Move> out) {
        int f = Square.file(sq);
        int r = Square.rank(sq);
        for (int[] d : dirs) {
            int nf = f + d[0];
            int nr = r + d[1];
            while (Square.onBoard(nf, nr)) {
                Piece target = board[Square.of(nf, nr)];
                if (target == null) {
                    out.add(new Move(sq, Square.of(nf, nr), null, Move.Flag.NORMAL));
                } else {
                    if (target.color() != sideToMove) {
                        out.add(new Move(sq, Square.of(nf, nr), null, Move.Flag.NORMAL));
                    }
                    break;
                }
                nf += d[0];
                nr += d[1];
            }
        }
    }

    /**
     * Castling needs the right still held (king and that rook never moved),
     * every square between them empty, and the king not in check, not
     * crossing an attacked square, and not landing on one. The rook — and on
     * the queenside the b-file square it passes — may be attacked freely.
     */
    private void castlingMoves(List<Move> out) {
        boolean white = sideToMove == Color.WHITE;
        int home = white ? 4 : 60;
        Color enemy = sideToMove.opposite();
        Piece rook = Piece.of(sideToMove, PieceKind.ROOK);
        if (board[home] != Piece.of(sideToMove, PieceKind.KING) || isAttacked(home, enemy)) {
            return;
        }
        int kingsideRight = white ? WHITE_KINGSIDE : BLACK_KINGSIDE;
        if ((castling & kingsideRight) != 0 && board[home + 3] == rook
                && board[home + 1] == null && board[home + 2] == null
                && !isAttacked(home + 1, enemy) && !isAttacked(home + 2, enemy)) {
            out.add(new Move(home, home + 2, null, Move.Flag.CASTLE_KINGSIDE));
        }
        int queensideRight = white ? WHITE_QUEENSIDE : BLACK_QUEENSIDE;
        if ((castling & queensideRight) != 0 && board[home - 4] == rook
                && board[home - 1] == null && board[home - 2] == null && board[home - 3] == null
                && !isAttacked(home - 1, enemy) && !isAttacked(home - 2, enemy)) {
            out.add(new Move(home, home - 2, null, Move.Flag.CASTLE_QUEENSIDE));
        }
    }

    /** The piece this move takes, if any — for en passant, the pawn beside the landing square. */
    public Piece capturedBy(Move m) {
        if (m.flag() == Move.Flag.EN_PASSANT) {
            return board[enPassantVictim(m)];
        }
        return board[m.to()];
    }

    private static int enPassantVictim(Move m) {
        return Square.of(Square.file(m.to()), Square.rank(m.from()));
    }

    /**
     * Plays a move without checking it — callers only ever pass moves taken
     * from {@link #legalMoves()} (or, internally, pseudo-legal candidates
     * being tested for legality).
     */
    public Position play(Move m) {
        Piece[] b = board.clone();
        Piece moving = b[m.from()];
        boolean capture = capturedBy(m) != null;
        b[m.from()] = null;
        if (m.flag() == Move.Flag.EN_PASSANT) {
            b[enPassantVictim(m)] = null;
        } else if (m.flag() == Move.Flag.CASTLE_KINGSIDE) {
            b[m.from() + 1] = b[m.from() + 3];
            b[m.from() + 3] = null;
        } else if (m.flag() == Move.Flag.CASTLE_QUEENSIDE) {
            b[m.from() - 1] = b[m.from() - 4];
            b[m.from() - 4] = null;
        }
        b[m.to()] = m.promotion() == null ? moving : Piece.of(moving.color(), m.promotion());

        int rights = castling;
        if (moving.kind() == PieceKind.KING) {
            rights &= moving.color() == Color.WHITE ? ~(WHITE_KINGSIDE | WHITE_QUEENSIDE) : ~(BLACK_KINGSIDE | BLACK_QUEENSIDE);
        }
        // A rook leaving its corner, or being captured on it, ends that right.
        rights &= ~cornerRight(m.from()) & ~cornerRight(m.to());

        int ep = m.flag() == Move.Flag.DOUBLE_PUSH ? (m.from() + m.to()) / 2 : Square.NONE;
        int half = moving.kind() == PieceKind.PAWN || capture ? 0 : halfmoveClock + 1;
        int full = sideToMove == Color.BLACK ? fullmoveNumber + 1 : fullmoveNumber;
        return new Position(b, sideToMove.opposite(), rights, ep, half, full);
    }

    private static int cornerRight(int sq) {
        return switch (sq) {
            case 0 -> WHITE_QUEENSIDE;
            case 7 -> WHITE_KINGSIDE;
            case 56 -> BLACK_QUEENSIDE;
            case 63 -> BLACK_KINGSIDE;
            default -> 0;
        };
    }

    // ---------------------------------------------------------------- draw facts

    /**
     * Identity for repetition (FIDE 9.2.2): same placement, same side to move,
     * same castling rights, and the same en passant possibility — where the
     * en passant square only counts if a capture onto it is actually legal.
     */
    public String repetitionKey() {
        boolean epMatters = epSquare != Square.NONE
                && legalMoves().stream().anyMatch(m -> m.flag() == Move.Flag.EN_PASSANT);
        return placementFen() + " " + (sideToMove == Color.WHITE ? "w" : "b") + " " + castlingFen()
                + " " + (epMatters ? Square.name(epSquare) : "-");
    }

    /**
     * A dead position (FIDE 5.2.2) detectable from material alone: neither
     * side can ever checkmate, by any series of legal moves. That's K v K, a
     * single minor piece against a bare king, or any number of bishops that
     * all stand on squares of one colour. Dead positions created by blocked
     * pawn structures can't be found this way and aren't attempted.
     */
    public boolean isDeadPosition() {
        int knights = 0;
        int bishops = 0;
        boolean lightBishop = false;
        boolean darkBishop = false;
        for (int sq = 0; sq < 64; sq++) {
            Piece p = board[sq];
            if (p == null) {
                continue;
            }
            switch (p.kind()) {
                case PAWN, ROOK, QUEEN -> {
                    return false;
                }
                case KNIGHT -> knights++;
                case BISHOP -> {
                    bishops++;
                    if (Square.isLight(sq)) lightBishop = true;
                    else darkBishop = true;
                }
                default -> {
                }
            }
        }
        if (knights + bishops <= 1) {
            return true;
        }
        return knights == 0 && !(lightBishop && darkBishop);
    }

    /**
     * Whether {@code side} could still deliver checkmate by some series of
     * legal moves, used when the other side's flag falls (FIDE 6.9). A bare
     * king never can; otherwise only a dead position rules it out — even a
     * lone knight can mate if the opponent's own pieces box their king in.
     */
    public boolean canEverCheckmate(Color side) {
        if (isDeadPosition()) {
            return false;
        }
        for (Piece p : board) {
            if (p != null && p.color() == side && p.kind() != PieceKind.KING) {
                return true;
            }
        }
        return false;
    }

    @Override
    public String toString() {
        return fen();
    }
}
