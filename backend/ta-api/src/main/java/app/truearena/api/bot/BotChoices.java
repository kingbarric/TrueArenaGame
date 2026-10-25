package app.truearena.api.bot;

import java.util.List;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.ToDoubleFunction;

/** Controlled legal variety, separate from the game rules and communication. */
final class BotChoices {
    static <T> T choose(List<T> legal, Difficulty level, ToDoubleFunction<T> score) {
        if (level == Difficulty.EASY && ThreadLocalRandom.current().nextInt(4) == 0) {
            return legal.get(ThreadLocalRandom.current().nextInt(legal.size()));
        }
        double best = legal.stream().mapToDouble(score).max().orElseThrow();
        double slack = level == Difficulty.EASY ? 25 : level == Difficulty.MEDIUM ? 5 : 0;
        List<T> candidates = legal.stream().filter(x -> score.applyAsDouble(x) >= best - slack).toList();
        return candidates.get(ThreadLocalRandom.current().nextInt(candidates.size()));
    }

    private BotChoices() {}
}
