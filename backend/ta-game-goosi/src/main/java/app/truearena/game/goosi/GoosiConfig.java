package app.truearena.game.goosi;

import app.truearena.engine.GameSettings;

/**
 * Oware Abapa always starts with four seeds in each of twelve houses. The
 * retained seed field keeps persisted room configuration compatible; only
 * the turn clock is a meaningful table option.
 */
public record GoosiConfig(int seedsPerPit, int turnSeconds) implements GameSettings {

    public GoosiConfig {
        if (seedsPerPit != 4) {
            throw new IllegalArgumentException("Oware starts with exactly four seeds per house");
        }
        if (turnSeconds < 10 || turnSeconds > 300) {
            throw new IllegalArgumentException("turnSeconds should be a sane number, got " + turnSeconds);
        }
    }

    public static GoosiConfig defaults() {
        return new GoosiConfig(4, 45);
    }
}
