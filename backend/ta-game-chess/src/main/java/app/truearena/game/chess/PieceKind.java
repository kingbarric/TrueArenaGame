package app.truearena.game.chess;

public enum PieceKind {
    PAWN('p'),
    KNIGHT('n'),
    BISHOP('b'),
    ROOK('r'),
    QUEEN('q'),
    KING('k');

    private final char letter;

    PieceKind(char letter) {
        this.letter = letter;
    }

    /** Lower-case FEN letter. */
    public char letter() {
        return letter;
    }

    /** The upper-case letter SAN uses — pawns have none. */
    public String sanLetter() {
        return this == PAWN ? "" : String.valueOf(Character.toUpperCase(letter));
    }

    public boolean isPromotionTarget() {
        return this == KNIGHT || this == BISHOP || this == ROOK || this == QUEEN;
    }

    public static PieceKind fromLetter(char c) {
        char lower = Character.toLowerCase(c);
        for (PieceKind k : values()) {
            if (k.letter == lower) {
                return k;
            }
        }
        return null;
    }
}
