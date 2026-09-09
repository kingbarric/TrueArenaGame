package app.truearena.engine;

import java.util.List;

/**
 * Opaque to the engine harness; each {@link GameModule} defines its own immutable
 * implementation. The few accessors here are what transport-agnostic code needs.
 */
public interface GameState {

    String phase();

    int round();

    boolean finished();

    /** Cumulative append-only log. {@link GameModule#drainEvents} returns the delta. */
    List<GameEvent> events();
}
