package app.truearena.engine.rating;

/**
 * One result against one opponent, from the rated player's point of view.
 *
 * <p>A multi-player game expands into several of these — one per opponent — all
 * fed into a single {@link Glicko2#update} call. That is what lets Draughts (one
 * opponent) and Ludo (three) use the same code path.
 *
 * @param opponent the opponent's rating state <em>before</em> the match
 * @param score    1.0 win, 0.5 draw, 0.0 loss
 */
public record MatchOutcome(RatingSnapshot opponent, double score) {

    public static final double WIN = 1.0;
    public static final double DRAW = 0.5;
    public static final double LOSS = 0.0;

    public MatchOutcome {
        if (opponent == null) {
            throw new IllegalArgumentException("opponent rating is required");
        }
        if (score < 0.0 || score > 1.0) {
            throw new IllegalArgumentException("score must be within [0, 1], got " + score);
        }
    }
}
