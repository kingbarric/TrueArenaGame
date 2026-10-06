package app.truearena.engine.rating;

import java.util.List;

/**
 * Glicko-2, implemented straight from Mark Glickman's published algorithm
 * ("Example of the Glicko-2 system", glicko.net/glicko/glicko2.pdf). Pure
 * functions, no state, no I/O — the official rating has to stay mathematically
 * reproducible and transparent, which means it must be testable against the
 * reference numbers rather than merely plausible.
 *
 * <p>Opponent quality is not special-cased anywhere below. It falls out of the
 * expected-score term {@code E(µ, µⱼ, φⱼ)}: beating a stronger opponent produces
 * a larger gain, losing to a weaker one a larger loss, and the {@code g(φⱼ)}
 * weighting means a result against an opponent we are still unsure about moves
 * you less than the same result against a well-established one.
 *
 * <p>A match is treated as a rating period of one. Multi-player games are
 * expanded pairwise by {@link PairwiseOutcomes} and evaluated in a single
 * update, which is the standard generalisation and keeps every game type on one
 * code path.
 */
public final class Glicko2 {

    /** Scale factor between the display (1500/350) scale and the internal µ/φ scale. */
    private static final double SCALE = 173.7178;

    /**
     * System constant τ, constraining how much volatility can move per period.
     * Glickman recommends 0.3–1.2; 0.5 is the usual choice and is conservative
     * enough that a single surprising result can't send a rating flying.
     */
    private static final double TAU = 0.5;

    private static final double CONVERGENCE = 0.000001;
    private static final int MAX_ITERATIONS = 100;

    private Glicko2() {
    }

    /**
     * The new state for one player after one rating period.
     *
     * <p>An empty {@code outcomes} is not an error: a player who didn't compete
     * keeps their rating but grows less certain, per the algorithm's step 6.
     */
    public static RatingSnapshot update(RatingSnapshot player, List<MatchOutcome> outcomes) {
        if (player == null) {
            throw new IllegalArgumentException("player rating is required");
        }
        double phi = player.deviation() / SCALE;
        double sigma = player.volatility();

        if (outcomes == null || outcomes.isEmpty()) {
            // Didn't play: rating unchanged, uncertainty grows.
            return new RatingSnapshot(player.rating(), Math.min(RatingSnapshot.INITIAL_DEVIATION,
                    Math.sqrt(phi * phi + sigma * sigma) * SCALE), sigma);
        }

        double mu = (player.rating() - RatingSnapshot.INITIAL_RATING) / SCALE;

        // Step 3 — estimated variance of the player's rating from game outcomes.
        double vInverse = 0.0;
        // Step 4 — the estimated improvement, pre-scaling.
        double deltaSum = 0.0;
        for (MatchOutcome outcome : outcomes) {
            double muJ = (outcome.opponent().rating() - RatingSnapshot.INITIAL_RATING) / SCALE;
            double phiJ = outcome.opponent().deviation() / SCALE;
            double g = g(phiJ);
            double e = expectedScore(mu, muJ, phiJ);
            vInverse += g * g * e * (1.0 - e);
            deltaSum += g * (outcome.score() - e);
        }
        if (vInverse == 0.0) {
            // Degenerate: every expected score was a certainty. Nothing to learn.
            return player;
        }
        double v = 1.0 / vInverse;
        double delta = v * deltaSum;

        // Step 5 — the new volatility, via Glickman's Illinois-algorithm iteration.
        double sigmaPrime = newVolatility(phi, sigma, v, delta);

        // Step 6/7 — pre-period deviation, then the new deviation and rating.
        double phiStar = Math.sqrt(phi * phi + sigmaPrime * sigmaPrime);
        double phiPrime = 1.0 / Math.sqrt(1.0 / (phiStar * phiStar) + vInverse);
        double muPrime = mu + phiPrime * phiPrime * deltaSum;

        return new RatingSnapshot(
                muPrime * SCALE + RatingSnapshot.INITIAL_RATING,
                phiPrime * SCALE,
                sigmaPrime);
    }

    /** Probability the player with {@code mu} scores against an opponent, on the internal scale. */
    private static double expectedScore(double mu, double muJ, double phiJ) {
        return 1.0 / (1.0 + Math.exp(-g(phiJ) * (mu - muJ)));
    }

    /** Weighting that discounts results against opponents whose own rating is uncertain. */
    private static double g(double phi) {
        return 1.0 / Math.sqrt(1.0 + 3.0 * phi * phi / (Math.PI * Math.PI));
    }

    /**
     * Glickman's step 5: solve for the volatility that best explains the period's
     * surprise, by root-finding on {@code f} with the Illinois variant of regula
     * falsi. Iteration-capped so a pathological input can never hang the game-end
     * path it runs on.
     */
    private static double newVolatility(double phi, double sigma, double v, double delta) {
        double a = Math.log(sigma * sigma);
        double A = a;
        double B;
        double deltaSq = delta * delta;
        double phiSq = phi * phi;

        if (deltaSq > phiSq + v) {
            B = Math.log(deltaSq - phiSq - v);
        } else {
            double k = 1.0;
            while (f(a - k * TAU, deltaSq, phiSq, v, a) < 0.0 && k < MAX_ITERATIONS) {
                k += 1.0;
            }
            B = a - k * TAU;
        }

        double fA = f(A, deltaSq, phiSq, v, a);
        double fB = f(B, deltaSq, phiSq, v, a);
        int iterations = 0;
        while (Math.abs(B - A) > CONVERGENCE && iterations++ < MAX_ITERATIONS) {
            double C = A + (A - B) * fA / (fB - fA);
            double fC = f(C, deltaSq, phiSq, v, a);
            if (fC * fB <= 0.0) {
                A = B;
                fA = fB;
            } else {
                fA = fA / 2.0;
            }
            B = C;
            fB = fC;
        }
        return Math.exp(A / 2.0);
    }

    private static double f(double x, double deltaSq, double phiSq, double v, double a) {
        double ex = Math.exp(x);
        double denominator = phiSq + v + ex;
        return (ex * (deltaSq - phiSq - v - ex)) / (2.0 * denominator * denominator)
                - (x - a) / (TAU * TAU);
    }
}
