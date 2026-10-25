package app.truearena.api.bot;

import org.springframework.stereotype.Component;
import org.springframework.beans.factory.annotation.Autowired;

/**
 * One {@link GameBotAdapter} instance per bot session (it's stateful, so it
 * can never be a shared singleton) — this just knows which class to `new`
 * for a given game type. Registering a new game's adapter here is the only
 * wiring change needed beyond writing the adapter itself.
 */
@Component
public class GameBotAdapterFactory {
    private final ChessMoveSource chess;
    private final DraughtsMoveSource draughts;

    public GameBotAdapterFactory() {
        this.chess = (position, history, level, budget) -> java.util.Optional.empty();
        this.draughts = (position, side, level, budget) -> java.util.Optional.empty();
    }

    @Autowired public GameBotAdapterFactory(StockfishEngine stockfish, ScanEngine scan) { this.chess = stockfish; this.draughts = scan; }

    /** Null if bots don't (yet) support this game type. */
    public GameBotAdapter create(String gameType) {
        return switch (gameType) {
            case "draughts" -> new DraughtsBotAdapter(draughts);
            case "chess" -> new ChessBotAdapter(chess);
            case "goosi" -> new GoosiBotAdapter();
            case "truearena" -> new TrueArenaBotAdapter();
            case "wordbluff" -> new WordBluffBotAdapter();
            case "whot" -> new WhotBotAdapter();
            case "ludo" -> new LudoBotAdapter();
            case "monopoly" -> new MonopolyBotAdapter();
            default -> null;
        };
    }
}
