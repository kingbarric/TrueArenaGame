package app.truearena.game.chess;

import app.truearena.engine.GameSettings;

/**
 * Time control, chosen by the host: each player starts with
 * {@code initialSeconds} on their own clock and gains {@code incrementSeconds}
 * after every move they complete (Fischer increment; 0 for sudden death).
 */
public record ChessConfig(int initialSeconds, int incrementSeconds) implements GameSettings {

    public ChessConfig {
        if (initialSeconds < 60 || initialSeconds > 3 * 60 * 60) {
            throw new IllegalArgumentException("initialSeconds should be between 1 minute and 3 hours, got " + initialSeconds);
        }
        if (incrementSeconds < 0 || incrementSeconds > 60) {
            throw new IllegalArgumentException("incrementSeconds should be between 0 and 60, got " + incrementSeconds);
        }
    }

    public static ChessConfig defaults() {
        return new ChessConfig(10 * 60, 0);
    }

    long initialMs() {
        return initialSeconds * 1000L;
    }

    long incrementMs() {
        return incrementSeconds * 1000L;
    }
}
