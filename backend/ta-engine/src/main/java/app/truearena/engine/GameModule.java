package app.truearena.engine;

import java.util.List;
import java.util.Optional;

/**
 * A pluggable rule set. Pure and framework-free (Build Brief §8). All state transitions
 * return a fresh {@link GameState}; {@link #drainEvents} yields the log entries produced
 * between two consecutive states.
 *
 * <p><b>Non-negotiable:</b> {@link #visibleStateFor} and {@link #broadcastState} must never
 * expose another player's secret role before the final reveal.
 */
public interface GameModule {

    String gameType();

    /** The ordered phase template for one round loop, used for timers and the WS contract. */
    List<Phase> definePhases(GameConfig config);

    GameState initialState(List<String> playerIds, GameConfig config, RandomSource rng);

    /** Apply a player/host action. Idempotent on {@link PlayerAction#actionId()}. */
    GameState onPlayerAction(GameState state, PlayerAction action);

    /** Advance because the named phase's timer elapsed (or the host advanced it). */
    GameState onPhaseElapsed(GameState state, String endedPhase);

    Optional<WinResult> checkWinCondition(GameState state);

    PlayerVisibleState visibleStateFor(GameState state, String playerId);

    PublicBroadcastState broadcastState(GameState state);

    /** Log entries added between {@code prev} and {@code next}. */
    List<GameEvent> drainEvents(GameState prev, GameState next);
}
