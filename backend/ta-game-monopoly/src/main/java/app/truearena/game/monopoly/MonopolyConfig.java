package app.truearena.game.monopoly;

import app.truearena.engine.GameSettings;

public record MonopolyConfig(int decisionSeconds) implements GameSettings {
  public static final int MIN_PLAYERS = 2, MAX_PLAYERS = 8;

  public MonopolyConfig {
    if (decisionSeconds < 30 || decisionSeconds > 600)
      throw new IllegalArgumentException("decisionSeconds");
  }

  public static MonopolyConfig defaults() {
    return new MonopolyConfig(180);
  }
}
