package app.truearena.game.draughts;

import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class DraughtsDrawTest {
    private final DraughtsModule module = new DraughtsModule();

    @Test
    void agreedDrawIsAnAuthoritativeTerminalResult() {
        var start = (DraughtsState) module.initialState(List.of("a", "b"),
                DraughtsConfig.defaults(), RandomSource.seeded(4));
        var offered = module.onPlayerAction(start, PlayerAction.of(start.playerA, "OFFER_DRAW", Map.of()));
        assertThat(module.checkWinCondition(offered)).isEmpty();
        assertThatThrownBy(() -> module.onPlayerAction(offered,
                PlayerAction.of(start.playerA, "ACCEPT_DRAW", Map.of())))
                .isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", "NO_DRAW_OFFER");
        var drawn = module.onPlayerAction(offered, PlayerAction.of(start.playerB, "ACCEPT_DRAW", Map.of()));
        assertThat(drawn.finished()).isTrue();
        assertThat(module.checkWinCondition(drawn).orElseThrow().winningSide()).isEqualTo("draw");
        assertThat(module.checkWinCondition(drawn).orElseThrow().perPlayerOutcome())
                .containsEntry(start.playerA, "tied").containsEntry(start.playerB, "tied");
    }

    @Test
    void aMoveWithdrawsTheDrawOffer() {
        var start = (DraughtsState) module.initialState(List.of("a", "b"),
                DraughtsConfig.defaults(), RandomSource.seeded(4));
        var offered = module.onPlayerAction(start, PlayerAction.of(start.playerB, "OFFER_DRAW", Map.of()));
        var moved = module.onPlayerAction(offered, PlayerAction.of(start.playerA, "MOVE",
                Map.of("from", Board.squareOf(3, 0), "to", Board.squareOf(4, 1))));
        assertThatThrownBy(() -> module.onPlayerAction(moved,
                PlayerAction.of(start.playerA, "ACCEPT_DRAW", Map.of())))
                .isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", "NO_DRAW_OFFER");
    }
}
