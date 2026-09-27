package app.truearena.api.bot;

import org.springframework.stereotype.Component;

/**
 * One {@link GameBotAdapter} instance per bot session (it's stateful, so it
 * can never be a shared singleton) — this just knows which class to `new`
 * for a given game type. Registering a new game's adapter here is the only
 * wiring change needed beyond writing the adapter itself.
 */
@Component
public class GameBotAdapterFactory {

    /** Null if bots don't (yet) support this game type. */
    public GameBotAdapter create(String gameType) {
        return switch (gameType) {
            case "draughts" -> new DraughtsBotAdapter();
            case "goosi" -> new GoosiBotAdapter();
            case "truearena" -> new TrueArenaBotAdapter();
            case "wordbluff" -> new WordBluffBotAdapter();
            case "whot" -> new WhotBotAdapter();
            default -> null;
        };
    }
}
