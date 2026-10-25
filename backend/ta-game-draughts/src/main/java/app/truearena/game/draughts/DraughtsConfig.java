package app.truearena.game.draughts;

import app.truearena.engine.GameSettings;

/**
 * Draughts' settings, chosen by the host when the room is made.
 *
 * <p>{@code mandatoryCapture} is the main house rule. On, as in
 * international draughts, a capture must be taken, and it must be the
 * sequence that takes the most pieces. Off (the casual default), a capture
 * is simply one of the moves available. Either way
 * a capture sequence you *start* must be finished: the piece keeps jumping
 * while it still can.
 *
 * <p>{@code seizure} (only with captures optional): a player who could have
 * captured but played a plain move instead loses one of the pieces that
 * could have taken — the opponent may seize it before their own move.
 */
public record DraughtsConfig(int turnSeconds, boolean mandatoryCapture, boolean seizure) implements GameSettings {

    public DraughtsConfig {
        if (turnSeconds < 10 || turnSeconds > 300) {
            throw new IllegalArgumentException("turnSeconds should be a sane number, got " + turnSeconds);
        }
        // With captures forced nobody can miss one, so there's nothing to seize.
        if (mandatoryCapture) seizure = false;
    }

    public DraughtsConfig(int turnSeconds, boolean mandatoryCapture) {
        this(turnSeconds, mandatoryCapture, false);
    }

    public static DraughtsConfig defaults() {
        return new DraughtsConfig(60, false);
    }
}
