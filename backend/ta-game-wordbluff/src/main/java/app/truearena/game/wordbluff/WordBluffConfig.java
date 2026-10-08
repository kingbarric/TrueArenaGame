package app.truearena.game.wordbluff;

import app.truearena.engine.GameSettings;

/**
 * Word Bluff's settings. Its own type rather than
 * {@code app.truearena.engine.GameConfig} — that record is TrueArena-shaped
 * (traitor curves, night-kill rules, …) and isn't a generic cross-game config.
 * Implements the {@link GameSettings} marker interface so {@link WordBluffModule}
 * can be a real {@code app.truearena.engine.GameModule} and run through the
 * same {@code GameOrchestrator}/WS transport as TrueArena.
 */
public record WordBluffConfig(int targetScore, int turnSeconds, boolean textMode) implements GameSettings {

    public WordBluffConfig(int targetScore, int turnSeconds) {
        this(targetScore, turnSeconds, false);
    }

    public WordBluffConfig {
        if (targetScore < 10 || targetScore > 200) {
            throw new IllegalArgumentException("targetScore should be a sane party-game number, got " + targetScore);
        }
        if (turnSeconds < 15 || turnSeconds > 180) {
            throw new IllegalArgumentException("turnSeconds should be a sane party-game number, got " + turnSeconds);
        }
    }

    public static WordBluffConfig defaults() {
        return new WordBluffConfig(30, 60);
    }
}
