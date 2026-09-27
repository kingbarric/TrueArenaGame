package app.truearena.game.whot;

/**
 * One card: a shape and a number.
 *
 * <p>The deck has no 6 and no 9 — upside down they're the same card, which is
 * why the traditional deck leaves them out.
 */
public record WhotCard(Shape shape, int number) {

    /** The Whot card's number, and the only number the WHOT shape ever carries. */
    public static final int WHOT_NUMBER = 20;

    public enum Shape {
        CIRCLE, TRIANGLE, CROSS, SQUARE, STAR,
        /** The wild card. Matches anything, and its holder names the shape to follow. */
        WHOT
    }

    public boolean isWhot() {
        return shape == Shape.WHOT;
    }

    /** How this card is written on the wire: "circle-5", "whot-20". */
    public String code() {
        return shape.name().toLowerCase() + "-" + number;
    }

    public static WhotCard parse(String code) {
        int dash = code.lastIndexOf('-');
        if (dash < 0) {
            throw new IllegalArgumentException("not a card: " + code);
        }
        return new WhotCard(
                Shape.valueOf(code.substring(0, dash).toUpperCase()),
                Integer.parseInt(code.substring(dash + 1)));
    }
}
