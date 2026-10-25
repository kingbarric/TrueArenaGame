package app.truearena.engine;

import java.util.List;
import java.util.Optional;
import java.util.function.Function;
import java.util.function.ToDoubleFunction;

/** Iterative alpha-beta over real reducers. Only fully completed depths replace the last result. */
public final class GameTreeSearch {
    private final GameModule game;
    private final String player;
    private final Function<GameState, List<PlayerAction>> actions;
    private final ToDoubleFunction<GameState> evaluation;
    private final long deadline;
    private int nodes;

    private GameTreeSearch(GameModule game, String player, Function<GameState, List<PlayerAction>> actions,
                           ToDoubleFunction<GameState> evaluation, long millis) {
        this.game = game;
        this.player = player;
        this.actions = actions;
        this.evaluation = evaluation;
        this.deadline = System.nanoTime() + millis * 1_000_000;
    }

    public static Optional<PlayerAction> choose(GameModule game, GameState root, String player,
            Function<GameState, List<PlayerAction>> actions, ToDoubleFunction<GameState> evaluation,
            int depth, long millis) {
        List<PlayerAction> legal = actions.apply(root);
        if (legal.isEmpty()) return Optional.empty();
        GameTreeSearch search = new GameTreeSearch(game, player, actions, evaluation, millis);
        PlayerAction best = legal.getFirst();
        for (int d = 1; d <= depth; d++) {
            try {
                double value = Double.NEGATIVE_INFINITY;
                PlayerAction candidate = best;
                for (PlayerAction action : legal) {
                    search.checkBudget();
                    double score = search.visit(game.onPlayerAction(root, action), d - 1,
                            value, Double.POSITIVE_INFINITY);
                    if (score > value) { value = score; candidate = action; }
                }
                best = candidate;
            } catch (BudgetExhausted ignored) {
                break;
            }
        }
        return Optional.of(best);
    }

    private double visit(GameState state, int depth, double alpha, double beta) {
        checkBudget();
        if (state.finished() || depth == 0) return evaluation.applyAsDouble(state);
        List<PlayerAction> legal = actions.apply(state);
        if (legal.isEmpty()) return evaluation.applyAsDouble(state);
        boolean maximise = player.equals(legal.getFirst().actor());
        double value = maximise ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY;
        for (PlayerAction action : legal) {
            double score = visit(game.onPlayerAction(state, action), depth - 1, alpha, beta);
            value = maximise ? Math.max(value, score) : Math.min(value, score);
            if (maximise) alpha = Math.max(alpha, value); else beta = Math.min(beta, value);
            if (alpha >= beta) break;
        }
        return value;
    }

    private void checkBudget() {
        if (++nodes > 4000 || System.nanoTime() >= deadline || Thread.currentThread().isInterrupted())
            throw new BudgetExhausted();
    }

    private static final class BudgetExhausted extends RuntimeException {
        BudgetExhausted() { super(null, null, false, false); }
    }

    private GameTreeSearch() { throw new UnsupportedOperationException(); }
}
