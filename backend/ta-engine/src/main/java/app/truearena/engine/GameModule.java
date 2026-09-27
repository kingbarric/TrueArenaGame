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
    List<Phase> definePhases(GameSettings config);

    GameState initialState(List<String> playerIds, GameSettings config, RandomSource rng);

    /** Apply a player/host action. Idempotent on {@link PlayerAction#actionId()}. */
    GameState onPlayerAction(GameState state, PlayerAction action);

    /** Advance because the named phase's timer elapsed (or the host advanced it). */
    GameState onPhaseElapsed(GameState state, String endedPhase);

    Optional<WinResult> checkWinCondition(GameState state);

    PlayerVisibleState visibleStateFor(GameState state, String playerId);

    PublicBroadcastState broadcastState(GameState state);

    /** Log entries added between {@code prev} and {@code next}. */
    List<GameEvent> drainEvents(GameState prev, GameState next);

    /**
     * Whether each player holds private state that changes as the game is
     * played, and so has to be re-sent to them after every action.
     *
     * <p>Most games here are played on an open board: everything worth
     * knowing is in the public broadcast, and a player's own view only
     * matters when they join or reconnect. A card game is the exception —
     * your hand changes on your own turn and on everyone else's, and it
     * can't ride the public frame without showing it to the table. Those
     * modules return {@code true} and the orchestrator sends each player
     * their own view alongside the public one.
     */
    default boolean hasPrivatePlayerState() {
        return false;
    }
}
