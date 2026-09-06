package app.truearena.engine;

/**
 * Marker for a pluggable game rule set. The full contract (definePhases, onPlayerAction,
 * checkWinCondition, getVisibleStateFor, getBroadcastState, ...) lands in Phase 5.1.
 */
public interface GameModule {

    /** Stable identifier stored on {@code game_sessions.game_type}. */
    String gameType();
}
