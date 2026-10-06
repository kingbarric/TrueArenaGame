package app.truearena.game.chess;

public enum Color {
    WHITE("white"),
    BLACK("black");

    private final String wire;

    Color(String wire) {
        this.wire = wire;
    }

    public Color opposite() {
        return this == WHITE ? BLACK : WHITE;
    }

    /** Lower-case name used on the wire and as the {@code winningSide} of a result. */
    public String wire() {
        return wire;
    }
}
