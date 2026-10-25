package app.truearena.api.bot;

import app.truearena.engine.*;
import app.truearena.game.draughts.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import java.util.*;
import static org.assertj.core.api.Assertions.assertThat;

@EnabledIfSystemProperty(named = "scan.test.path", matches = ".+")
class ScanRealEngineTest {
    private ScanEngine engine() {
        return new ScanEngine(new ScanEngine.Settings(true, System.getProperty("scan.test.path"),
                System.getProperty("scan.test.directory"), 1, 20, 100));
    }

    @Test void allLevelsPlayBothSidesThroughTheRealGameWithoutFallback() {
        try (var engine = engine()) {
            engine.warmUp();
            var game = new DraughtsModule();
            for (Difficulty level : Difficulty.values()) {
                GameState state = game.initialState(List.of("a", "b"), new DraughtsConfig(60, true), RandomSource.seeded(77));
                Map<String, GameBotAdapter> bots = Map.of("a", new DraughtsBotAdapter(engine), "b", new DraughtsBotAdapter(engine));
                for (int action = 0; action < 36 && !state.finished(); action++) {
                    String actor = game.playersToAct(state).iterator().next();
                    GameBotAdapter bot = bots.get(actor);
                    assertThat(bot.onFrame("SNAPSHOT", game.visibleStateFor(state, actor).data(), actor, level)).isPresent();
                    state = game.onPlayerAction(state, bot.decideLocally(actor, level).orElseThrow());
                }
            }
            assertThat((Long) engine.status().get("scanTurns")).isGreaterThan(30);
            assertThat(engine.status()).containsEntry("fallbackRequests", 0L);
        }
    }

    @Test void flyingKingCapturesRespectBlockedVictimsAndBothSquareOrientations() {
        try (var engine = engine()) {
            engine.warmUp();
            for (String side : List.of("A", "B")) {
                Piece[] board = new Piece[50];
                int from = Board.squareOf(4, 5);
                board[from] = side.equals("A") ? Piece.A_KING : Piece.B_KING;
                board[Board.squareOf(3, 4)] = side.equals("A") ? Piece.B_MAN : Piece.A_MAN;
                board[Board.squareOf(5, 6)] = side.equals("A") ? Piece.B_MAN : Piece.A_MAN;
                var result = engine.choose(board, side, Difficulty.HARD, 1500).orElseThrow();
                assertThat(result).hasSize(1);
                assertThat(result.getFirst().from()).isEqualTo(from);
            }
            assertThat(engine.status()).containsEntry("fallbackRequests", 0L);
        }
    }
}
