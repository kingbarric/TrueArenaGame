package app.truearena.game.draughts;

import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import org.junit.jupiter.api.Test;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import static org.assertj.core.api.Assertions.assertThat;

class DraughtsEffectsTest {
    private final DraughtsModule module = new DraughtsModule();
    private DraughtsState fresh(long seed) {
        return (DraughtsState) module.initialState(List.of("a", "b"), DraughtsConfig.defaults(), RandomSource.seeded(seed));
    }
    @Test void randomFinisherIsSeededVariesByGameAndSurvivesStateChanges() {
        var effects = new HashSet<String>();
        for (int seed = 0; seed < 50; seed++) {
            var start = fresh(seed);
            effects.add(start.finishEffect);
            assertThat(fresh(seed).finishEffect).isEqualTo(start.finishEffect);
            var end = (DraughtsState) module.onPlayerAction(start, PlayerAction.of(start.playerA, "FORFEIT", Map.of()));
            assertThat(end.finishEffect).isEqualTo(start.finishEffect);
            var over = end.events().getLast();
            assertThat(over.type()).isEqualTo("GAME_OVER");
            assertThat(over.payload()).containsEntry("finishEffect", start.finishEffect);
            assertThat(module.visibleStateFor(end, end.playerA).data())
                    .containsEntry("seq", end.seq).containsEntry("finishEffect", start.finishEffect)
                    .containsEntry("winningSide", "B");
            assertThat(module.broadcastState(end).data()).isEqualTo(module.visibleStateFor(end, end.playerA).data());
        }
        assertThat(effects).containsExactlyInAnyOrder("royal", "thunder", "fire", "neon", "confetti");
    }
    @Test void kingCapturePublishesTheVictimTypeAndTheActualFinishReason() {
        var d = new DraughtsState.Draft(fresh(7));
        d.board = new Piece[Board.SIZE];
        int from = Board.squareOf(4, 1), victim = Board.squareOf(5, 2), to = Board.squareOf(6, 3);
        d.board[from] = Piece.A_MAN; d.board[victim] = Piece.B_KING;
        d.phase = "TurnA"; d.requiredCaptureCount = 0;
        var end = (DraughtsState) module.onPlayerAction(d.build(), PlayerAction.of(d.playerA, "MOVE", Map.of("from", from, "to", to)));
        var captured = end.events().stream().filter(e -> e.type().equals("PIECE_CAPTURED")).findFirst().orElseThrow();
        assertThat(captured.payload()).containsEntry("capturedKing", true).containsEntry("captureCount", 1);
        assertThat(end.board[to]).isEqualTo(Piece.A_MAN);
        assertThat(end.board[victim]).isNull();
        assertThat(end.events().getLast().payload()).containsEntry("reason", "capture");
    }
    @Test void aDrawDoesNotRequestAVictoryCelebration() {
        var start = fresh(9);
        var offer = module.onPlayerAction(start, PlayerAction.of(start.playerA, "OFFER_DRAW", Map.of()));
        var end = module.onPlayerAction(offer, PlayerAction.of(start.playerB, "ACCEPT_DRAW", Map.of()));
        assertThat(end.events().getLast().payload()).containsEntry("winningSide", "draw").doesNotContainKey("finishEffect");
    }
}
