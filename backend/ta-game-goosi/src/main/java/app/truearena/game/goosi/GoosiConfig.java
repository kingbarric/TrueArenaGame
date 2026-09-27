package app.truearena.game.goosi;

import app.truearena.engine.GameSettings;

/**
 * Goosi's settings — a 16-pit sowing/capture board (2 or 4 players share the
 * same fixed 16 pits, see {@link GoosiModule}), so the only real knob is how
 * many seeds each pit starts with, plus the usual per-turn clock.
 */
public record GoosiConfig(int seedsPerPit, int turnSeconds) implements GameSettings {

    public GoosiConfig {
        if (seedsPerPit < 1 || seedsPerPit > 10) {
            throw new IllegalArgumentException("seedsPerPit should be a sane number, got " + seedsPerPit);
        }
        if (turnSeconds < 10 || turnSeconds > 300) {
            throw new IllegalArgumentException("turnSeconds should be a sane number, got " + turnSeconds);
        }
    }

    public static GoosiConfig defaults() {
        return new GoosiConfig(4, 45);
    }
}
