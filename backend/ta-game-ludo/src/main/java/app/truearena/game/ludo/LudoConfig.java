package app.truearena.game.ludo;

import app.truearena.engine.GameSettings;

public record LudoConfig(int turnSeconds, int twoPlayerPieces) implements GameSettings {
    public LudoConfig(int turnSeconds) { this(turnSeconds, 4); }

    public LudoConfig {
        if (turnSeconds < 15 || turnSeconds > 180) {
            throw new IllegalArgumentException("turnSeconds must be 15 to 180");
        }
        if (twoPlayerPieces != 4 && twoPlayerPieces != 8) {
            throw new IllegalArgumentException("twoPlayerPieces must be 4 or 8");
        }
    }

    public static LudoConfig defaults() {
        return new LudoConfig(60);
    }
}
