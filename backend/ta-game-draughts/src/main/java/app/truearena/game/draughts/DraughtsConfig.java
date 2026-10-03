package app.truearena.game.draughts;

import app.truearena.engine.GameSettings;

/**
 * Draughts' settings, chosen by the host when the room is made.
 *
 * <p>{@code mandatoryCapture} is the one real house rule. On, as in
 * international draughts, a capture must be taken, and it must be the
 * sequence that takes the most pieces. Off (the casual default), a capture
 * is simply one of the moves available. Either way
 * a capture sequence you *start* must be finished: the piece keeps jumping
 * while it still can.
 */
public record DraughtsConfig(int turnSeconds, boolean mandatoryCapture) implements GameSettings {

    public DraughtsConfig {
        if (turnSeconds < 10 || turnSeconds > 300) {
            throw new IllegalArgumentException("turnSeconds should be a sane number, got " + turnSeconds);
        }
    }

    public static DraughtsConfig defaults() {
        return new DraughtsConfig(60, false);
    }
}
