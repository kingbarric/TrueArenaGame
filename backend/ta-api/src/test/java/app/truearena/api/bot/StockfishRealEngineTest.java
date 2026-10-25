package app.truearena.api.bot;

import app.truearena.engine.*;
import app.truearena.game.chess.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

@EnabledIfSystemProperty(named = "stockfish.test.path", matches = ".+")
class StockfishRealEngineTest {
    private StockfishEngine engine() {
        return new StockfishEngine(new StockfishEngine.Settings(true, System.getProperty("stockfish.test.path"), 1, 16, 200, 0));
    }

    @Test void legendFindsCheckmateAndPromotionUsingTheRealExecutable() {
        try (var engine = engine()) {
            engine.warmUp();
            for (String fen : List.of("7k/5Q2/6K1/8/8/8/8/8 w - - 0 1", "7k/P7/6K1/8/8/8/8/8 w - - 0 1")) {
                Position position = Position.fromFen(fen);
                Move move = engine.choose(position, List.of(), Difficulty.HARD, 1000).orElseThrow();
                Position next = position.play(move);
                assertThat(next.inCheck()).isTrue();
                assertThat(next.legalMoves()).isEmpty();
            }
            assertThat(engine.status()).containsEntry("fallbackRequests", 0L).containsEntry("stockfishMoves", 2L);
        }
    }

    @Test void allThreeLevelsPlayLegalMovesThroughTheAdapterWithoutFallback() {
        try (var engine = engine()) {
            engine.warmUp();
            var module = new ChessModule();
            long moves = 0;
            for (Difficulty level : Difficulty.values()) {
                GameState state = module.initialState(List.of("bot", "human"), ChessConfig.defaults(), RandomSource.seeded(17));
                var adapter = new ChessBotAdapter(engine);
                adapter.pacing = false;
                adapter.thinkCapMs = 1000;
                for (int ply = 0; ply < 12 && !state.finished(); ply++) {
                    Map<String, Object> view = module.visibleStateFor(state, "bot").data();
                    String actor = module.playersToAct(state).iterator().next();
                    PlayerAction action;
                    if (actor.equals("bot")) {
                        assertThat(adapter.onFrame("SNAPSHOT", view, "bot", level)).isPresent();
                        action = adapter.decideLocally("bot", level).orElseThrow();
                        moves++;
                    } else {
                        Move move = Position.fromFen((String) view.get("fen")).legalMoves().getFirst();
                        var data = new java.util.HashMap<String, Object>(Map.of("from", Square.name(move.from()), "to", Square.name(move.to())));
                        if (move.promotion() != null) data.put("promotion", String.valueOf(move.promotion().letter()));
                        action = PlayerAction.of(actor, "MOVE", data);
                    }
                    state = module.onPlayerAction(state, action);
                }
            }
            assertThat(moves).isGreaterThan(6);
            assertThat(engine.status()).containsEntry("stockfishMoves", moves).containsEntry("fallbackRequests", 0L);
        }
    }
}
