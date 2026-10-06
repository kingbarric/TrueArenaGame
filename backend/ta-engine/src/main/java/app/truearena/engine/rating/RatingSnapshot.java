package app.truearena.engine.rating;

/**
 * A player's Glicko-2 state for one game type, on the familiar 1500/350 display
 * scale (the internal µ/φ scale never leaves {@link Glicko2}).
 *
 * <p>{@code deviation} is the uncertainty: a fresh account starts at the maximum
 * so the system can find its level in a handful of games, and it shrinks as that
 * level becomes clear. {@code volatility} is how erratic the player's results
 * are, and is what lets a genuinely improving player move faster than a steady
 * one.
 */
public record RatingSnapshot(double rating, double deviation, double volatility) {

    /** Rating every account starts on, for every game, independently. */
    public static final double INITIAL_RATING = 1500.0;

    /** Maximum uncertainty — "we know nothing about this player yet". */
    public static final double INITIAL_DEVIATION = 350.0;

    /** Glickman's suggested starting volatility. */
    public static final double INITIAL_VOLATILITY = 0.06;

    public static RatingSnapshot initial() {
        return new RatingSnapshot(INITIAL_RATING, INITIAL_DEVIATION, INITIAL_VOLATILITY);
    }
}
