package app.truearena.engine;

import java.util.List;

/**
 * Thin orchestration around a {@link GameModule}: apply a step, collect its events, and
 * surface a win result. The single-writer lock and event persistence live in {@code ta-room}.
 */
public final class GameRunner {

    private final GameModule module;

    public GameRunner(GameModule module) {
        this.module = module;
    }

    public GameModule module() {
        return module;
    }

    public Step apply(GameState state, PlayerAction action) {
        GameState next = module.onPlayerAction(state, action);
        return step(state, next);
    }

    public Step elapse(GameState state, String endedPhase) {
        GameState next = module.onPhaseElapsed(state, endedPhase);
        return step(state, next);
    }

    private Step step(GameState prev, GameState next) {
        List<GameEvent> events = module.drainEvents(prev, next);
        return new Step(next, events, module.checkWinCondition(next).orElse(null));
    }

    public record Step(GameState state, List<GameEvent> events, WinResult win) {
        public boolean finished() {
            return win != null || state.finished();
        }
    }
}
