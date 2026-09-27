package app.truearena.game.draughts;

/**
 * What's on one square. A board slot is a nullable {@code Piece} reference —
 * {@code null} means empty.
 */
public enum Piece {
    A_MAN, A_KING, B_MAN, B_KING;

    public String side() {
        return (this == A_MAN || this == A_KING) ? DraughtsState.SIDE_A : DraughtsState.SIDE_B;
    }

    public boolean isKing() {
        return this == A_KING || this == B_KING;
    }

    /** A man reaching the far row becomes its side's king; a king stays a king. */
    public Piece promoted() {
        return switch (this) {
            case A_MAN -> A_KING;
            case B_MAN -> B_KING;
            default -> this;
        };
    }
}
