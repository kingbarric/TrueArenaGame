package app.truearena.engine;

/**
 * Marker interface every game type's settings record implements, so
 * {@link GameModule} and the room/orchestration layer can hold "some game's
 * config" without knowing which game. {@link GameConfig} (TrueArena) is the
 * first implementation; {@code app.truearena.game.wordbluff.WordBluffConfig}
 * is the second. Deliberately empty — each game defines its own concrete
 * fields and casts back to its own type inside its own {@link GameModule}.
 */
public interface GameSettings {
}
