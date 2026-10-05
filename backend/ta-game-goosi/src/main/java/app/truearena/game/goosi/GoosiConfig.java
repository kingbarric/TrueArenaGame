package app.truearena.game.goosi;

import app.truearena.engine.GameSettings;

/**
 * Macala starts with four seeds in each of twelve houses. The
 * retained seed field keeps persisted room configuration compatible; only
 * the turn clock is a meaningful table option.
 */
public record GoosiConfig(int seedsPerPit, int turnSeconds, String mode) implements GameSettings {

    public static final String RELAY = "relay";
    public static final String OWARE = "oware";

    public GoosiConfig {
        if (seedsPerPit != 4) {
            throw new IllegalArgumentException("Macala starts with exactly four seeds per house");
        }
        if (turnSeconds < 10 || turnSeconds > 300) {
            throw new IllegalArgumentException("turnSeconds should be a sane number, got " + turnSeconds);
        }
        if (!RELAY.equals(mode) && !OWARE.equals(mode)) {
            throw new IllegalArgumentException("unknown Macala mode: " + mode);
        }
    }

    public static GoosiConfig defaults() {
        return new GoosiConfig(4, 45, RELAY);
    }
}
