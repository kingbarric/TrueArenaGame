package app.truearena.game.chess;

/**
 * One move. {@code promotion} is non-null exactly when a pawn reaches the
 * last rank — each of the four choices is a distinct move.
 */
public record Move(int from, int to, PieceKind promotion, Flag flag) {

    public enum Flag {
        NORMAL,
        DOUBLE_PUSH,
        EN_PASSANT,
        CASTLE_KINGSIDE,
        CASTLE_QUEENSIDE
    }

    public boolean isCastle() {
        return flag == Flag.CASTLE_KINGSIDE || flag == Flag.CASTLE_QUEENSIDE;
    }

    /** Long algebraic (UCI) form, e.g. {@code e2e4}, {@code e7e8q}. */
    public String uci() {
        return Square.name(from) + Square.name(to) + (promotion == null ? "" : String.valueOf(promotion.letter()));
    }
}
