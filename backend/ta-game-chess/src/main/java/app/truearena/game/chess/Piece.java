package app.truearena.game.chess;

public enum Piece {
    WHITE_PAWN(Color.WHITE, PieceKind.PAWN),
    WHITE_KNIGHT(Color.WHITE, PieceKind.KNIGHT),
    WHITE_BISHOP(Color.WHITE, PieceKind.BISHOP),
    WHITE_ROOK(Color.WHITE, PieceKind.ROOK),
    WHITE_QUEEN(Color.WHITE, PieceKind.QUEEN),
    WHITE_KING(Color.WHITE, PieceKind.KING),
    BLACK_PAWN(Color.BLACK, PieceKind.PAWN),
    BLACK_KNIGHT(Color.BLACK, PieceKind.KNIGHT),
    BLACK_BISHOP(Color.BLACK, PieceKind.BISHOP),
    BLACK_ROOK(Color.BLACK, PieceKind.ROOK),
    BLACK_QUEEN(Color.BLACK, PieceKind.QUEEN),
    BLACK_KING(Color.BLACK, PieceKind.KING);

    private final Color color;
    private final PieceKind kind;

    Piece(Color color, PieceKind kind) {
        this.color = color;
        this.kind = kind;
    }

    public Color color() {
        return color;
    }

    public PieceKind kind() {
        return kind;
    }

    public static Piece of(Color color, PieceKind kind) {
        return values()[(color == Color.WHITE ? 0 : 6) + kind.ordinal()];
    }

    /** FEN letter: upper case for White. */
    public char fen() {
        return color == Color.WHITE ? Character.toUpperCase(kind.letter()) : kind.letter();
    }

    public static Piece fromFen(char c) {
        PieceKind kind = PieceKind.fromLetter(c);
        if (kind == null) {
            return null;
        }
        return of(Character.isUpperCase(c) ? Color.WHITE : Color.BLACK, kind);
    }

    /** Two-letter code sent to clients, e.g. {@code wP}, {@code bK}. */
    public String code() {
        return (color == Color.WHITE ? "w" : "b") + Character.toUpperCase(kind.letter());
    }
}
