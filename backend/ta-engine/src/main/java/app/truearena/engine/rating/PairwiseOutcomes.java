package app.truearena.engine.rating;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Turns one finished game's {@code WinResult.perPlayerOutcome} — the
 * {@code playerId -> "won"|"lost"|"tied"} map every {@code GameModule} already
 * produces — into the per-player opponent lists Glicko-2 consumes.
 *
 * <p>Each player is scored against every other player in the game: finishing
 * above an opponent is a win against them, level is a draw, below is a loss.
 * A 1v1 Draughts game therefore yields one outcome per player, and a 4-player
 * Whot game yields three — same code, same rating maths, no per-game branches.
 * This is what makes the rating engine genuinely game-agnostic rather than
 * game-agnostic in the comments only.
 */
public final class PairwiseOutcomes {

    public static final String WON = "won";
    public static final String TIED = "tied";
    public static final String LOST = "lost";

    private PairwiseOutcomes() {
    }

    /**
     * @param outcomes {@code playerId -> outcome} for one finished game
     * @param ratings  pre-match rating state for each of those players
     * @return {@code playerId -> opponents-and-scores}, insertion-ordered to
     *         match {@code outcomes}. Players missing from {@code ratings}
     *         (a bot, a departed account) are left out of everyone's list and
     *         get no entry of their own, so an unrated participant simply
     *         doesn't exist as far as the maths is concerned.
     */
    public static Map<String, List<MatchOutcome>> expand(Map<String, String> outcomes,
                                                         Map<String, RatingSnapshot> ratings) {
        Map<String, List<MatchOutcome>> expanded = new LinkedHashMap<>();
        for (Map.Entry<String, String> self : outcomes.entrySet()) {
            RatingSnapshot own = ratings.get(self.getKey());
            if (own == null) {
                continue;
            }
            List<MatchOutcome> against = new ArrayList<>();
            for (Map.Entry<String, String> other : outcomes.entrySet()) {
                if (other.getKey().equals(self.getKey())) {
                    continue;
                }
                RatingSnapshot opponent = ratings.get(other.getKey());
                if (opponent == null) {
                    continue;
                }
                against.add(new MatchOutcome(opponent, score(self.getValue(), other.getValue())));
            }
            expanded.put(self.getKey(), against);
        }
        return expanded;
    }

    /** Score for the holder of {@code mine} against the holder of {@code theirs}. */
    public static double score(String mine, String theirs) {
        int comparison = Integer.compare(placement(mine), placement(theirs));
        if (comparison > 0) {
            return MatchOutcome.WIN;
        }
        return comparison == 0 ? MatchOutcome.DRAW : MatchOutcome.LOSS;
    }

    /**
     * Finishing position as an ordinal. An unrecognised outcome is treated as a
     * loss rather than throwing: a module adding a new outcome label must not be
     * able to break the game-end path.
     */
    private static int placement(String outcome) {
        return switch (outcome == null ? "" : outcome) {
            case WON -> 2;
            case TIED -> 1;
            default -> 0;
        };
    }
}
