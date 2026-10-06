package app.truearena.game.chess;

import java.util.List;

/** Standard algebraic notation for a legal move, as it would appear on a scoresheet. */
public final class San {

    private San() {
    }

    public static String of(Position before, Move move) {
        Position after = before.play(move);
        return body(before, move) + suffix(after);
    }

    private static String body(Position before, Move move) {
        if (move.flag() == Move.Flag.CASTLE_KINGSIDE) {
            return "O-O";
        }
        if (move.flag() == Move.Flag.CASTLE_QUEENSIDE) {
            return "O-O-O";
        }
        Piece moving = before.at(move.from());
        boolean capture = before.capturedBy(move) != null;
        String to = Square.name(move.to());
        if (moving.kind() == PieceKind.PAWN) {
            String file = capture ? (char) ('a' + Square.file(move.from())) + "x" : "";
            String promotion = move.promotion() == null ? "" : "=" + move.promotion().sanLetter();
            return file + to + promotion;
        }
        return moving.kind().sanLetter() + disambiguation(before, move, moving) + (capture ? "x" : "") + to;
    }

    /**
     * File if that's enough to tell the movers apart, else rank, else both —
     * only counting other pieces of the same kind that can legally reach the
     * same square (a pinned twin doesn't need distinguishing).
     */
    private static String disambiguation(Position before, Move move, Piece moving) {
        if (moving.kind() == PieceKind.KING) {
            return "";
        }
        List<Move> rivals = before.legalMoves().stream()
                .filter(m -> m.to() == move.to() && m.from() != move.from() && before.at(m.from()) == moving)
                .toList();
        if (rivals.isEmpty()) {
            return "";
        }
        int file = Square.file(move.from());
        int rank = Square.rank(move.from());
        boolean fileUnique = rivals.stream().noneMatch(m -> Square.file(m.from()) == file);
        if (fileUnique) {
            return String.valueOf((char) ('a' + file));
        }
        boolean rankUnique = rivals.stream().noneMatch(m -> Square.rank(m.from()) == rank);
        if (rankUnique) {
            return String.valueOf((char) ('1' + rank));
        }
        return Square.name(move.from());
    }

    private static String suffix(Position after) {
        if (!after.inCheck()) {
            return "";
        }
        return after.legalMoves().isEmpty() ? "#" : "+";
    }
}
