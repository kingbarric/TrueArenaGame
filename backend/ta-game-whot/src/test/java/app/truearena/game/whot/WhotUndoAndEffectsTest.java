package app.truearena.game.whot;

import app.truearena.engine.PlayerAction;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class WhotUndoAndEffectsTest {
    private final WhotModule game = new WhotModule();
    private WhotState table(int players) {
        var d = new WhotState.Draft(); d.config = WhotConfig.defaults();
        d.market.addAll(WhotModule.singleDeck(d.config));
        for (int i = 0; i < players; i++) d.players.add("p" + i);
        d.hands.put("p0", new ArrayList<>());
        for (String code : List.of("circle-2", "circle-14", "triangle-7")) {
            var card = WhotCard.parse(code); assertThat(d.market.remove(card)).isTrue(); d.hands.get("p0").add(card);
        }
        var top = WhotCard.parse("circle-5"); d.market.remove(top); d.pile.add(top);
        for (int i = 1; i < players; i++) d.hands.put("p" + i,
                new ArrayList<>(List.of(d.market.removeLast(), d.market.removeLast(), d.market.removeLast())));
        return d.build();
    }
    private WhotState act(WhotState state, String player, String action, Map<String, Object> data) {
        return (WhotState) game.onPlayerAction(state, PlayerAction.of(player, action, data));
    }
    private WhotState takeBack(WhotState state, int players) {
        state = act(state, "p0", "REQUEST_UNDO", Map.of());
        for (int i = 1; i < players; i++) state = act(state, "p" + i, "ACCEPT_UNDO", Map.of());
        return state;
    }

    @Test void everyOtherPlayerMustAcceptAndTheExactPrivateStateIsRestored() {
        var before = table(4);
        var moved = act(before, "p0", "PLAY", Map.of("card", "circle-14"));
        assertThat(moved.hands.get("p1")).hasSize(4);
        var asked = act(moved, "p0", "REQUEST_UNDO", Map.of());
        asked = act(asked, "p1", "ACCEPT_UNDO", Map.of());
        asked = act(asked, "p2", "ACCEPT_UNDO", Map.of());
        assertThat(asked.hands).isEqualTo(moved.hands);
        var undo = PlayerAction.of("p3", "ACCEPT_UNDO", Map.of());
        var restored = (WhotState) game.onPlayerAction(asked, undo);
        assertThat(restored.hands).isEqualTo(before.hands);
        assertThat(restored.market).containsExactlyElementsOf(before.market);
        assertThat(restored.pile).containsExactlyElementsOf(before.pile);
        assertThat(restored.currentPlayer()).isEqualTo("p0");
        assertThat(restored.round).isGreaterThan(moved.round);
        assertThat(restored.seq).isGreaterThan(asked.seq);
        assertThat(restored.undoState).isNull();
        assertThat(restored.recentPlays.getLast()).containsEntry("undone", true);
        assertThat(game.onPlayerAction(restored, undo)).isSameAs(restored);
    }

    @Test void aPenaltyDrawRestoresTheSameMarketOrderAndDebt() {
        var d = new WhotState.Draft(table(2)); d.pendingPick = 6; var before = d.build();
        var drew = act(before, "p0", "DRAW", Map.of());
        var restored = takeBack(drew, 2);
        assertThat(restored.hands).isEqualTo(before.hands);
        assertThat(restored.market).containsExactlyElementsOf(before.market);
        assertThat(restored.pendingPick).isEqualTo(6);
        assertThat(restored.recentPlays.getLast()).doesNotContainKeys("cards", "hands", "market", "yourHand");
        assertThat(game.broadcastState(restored).data()).doesNotContainKeys("undoState", "hands", "market", "yourHand");
    }

    @Test void rejectionPlayAndTimeoutExpireARequestAndOnlyOneCheckpointIsRetained() {
        var moved = act(table(2), "p0", "PLAY", Map.of("card", "circle-2"));
        var asked = act(moved, "p0", "REQUEST_UNDO", Map.of());
        var refused = act(asked, "p1", "DECLINE_UNDO", Map.of());
        assertThat(refused.undoState).isNull();
        assertThatThrownBy(() -> act(refused, "p1", "ACCEPT_UNDO", Map.of())).isInstanceOf(RuleViolation.class);
        var continued = act(asked, "p1", "DRAW", Map.of());
        assertThat(continued.pendingUndo).isNull();
        assertThat(continued.lastMover).isEqualTo("p1");
        assertThat(continued.undoState.undoState).isNull();
        var paused = (WhotState) game.onPhaseElapsed(asked, "Turn");
        assertThat(paused.pendingUndo).isNull(); assertThat(paused.undoState).isNull();
        assertThatThrownBy(() -> act(moved, "p1", "REQUEST_UNDO", Map.of())).isInstanceOf(RuleViolation.class);
        assertThatThrownBy(() -> act(asked, "p0", "ACCEPT_UNDO", Map.of())).isInstanceOf(RuleViolation.class);
    }

    @Test void selectableFinishersCannotAlterCardsTurnsOrACompletedCelebration() {
        var before = table(2);
        var selected = act(before, "p0", "SELECT_FINISH_EFFECT", Map.of("effect", "royal"));
        assertThat(selected.hands).isEqualTo(before.hands);
        assertThat(selected.market).isEqualTo(before.market);
        assertThat(selected.round).isEqualTo(before.round);
        var d = new WhotState.Draft(selected); d.hands.put("p0", new ArrayList<>(List.of(WhotCard.parse("circle-2"))));
        var won = act(d.build(), "p0", "PLAY", Map.of("card", "circle-2"));
        assertThat(won.finished()).isTrue();
        assertThat(won.recentPlays.getLast()).containsEntry("kind", "finish").containsEntry("effect", "royal");
        assertThat(won.pendingPick).isZero(); // winning specials are not falsely animated as attacks
        assertThat(won.undoState).isNull();
        assertThat(act(won, "p0", "SELECT_FINISH_EFFECT", Map.of("effect", "fire"))).isSameAs(won);
        assertThatThrownBy(() -> act(before, "viewer", "SELECT_FINISH_EFFECT", Map.of("effect", "fire"))).isInstanceOf(RuleViolation.class);
        assertThatThrownBy(() -> act(before, "p0", "SELECT_FINISH_EFFECT", Map.of("effect", "unknown"))).isInstanceOf(RuleViolation.class);
    }

    @Test void momentPayloadReflectsRulesDebtAndTheActualNextSeat() {
        var played = act(table(4), "p0", "PLAY", Map.of("card", "circle-2"));
        assertThat(played.recentPlays.getLast()).containsEntry("kind", "pickTwo").containsEntry("debt", 2).containsEntry("target", "p1");
        var d = new WhotState.Draft(table(2)); d.config = new WhotConfig(60, 5, false, false, false, false, false, false);
        var ordinary = act(d.build(), "p0", "PLAY", Map.of("card", "circle-2"));
        assertThat(ordinary.recentPlays.getLast()).containsEntry("kind", "play").containsEntry("debt", 0);
        assertThat(played.recentPlays.getLast()).doesNotContainKeys("yourHand", "signalValid", "teamSignals", "market");
    }
    @Test void tellSignalsAndQualificationCloseTheTakeBackWindow() {
        var d = new WhotState.Draft(table(6));
        d.config = new WhotConfig(60, 5, false, true, true, true, true, true, "tell");
        d.stage = "qualification";
        d.teams.addAll(List.of(List.of("p0", "p1"), List.of("p2", "p3"), List.of("p4", "p5")));
        d.teamSignals.put(0, "🪐"); d.teamSignals.put(1, "🔮");
        var moved = act(d.build(), "p0", "PLAY", Map.of("card", "circle-2"));
        var asked = act(moved, "p0", "REQUEST_UNDO", Map.of());
        var signalled = act(asked, "p2", "SIGNAL", Map.of("symbol", "🔮"));
        assertThat(signalled.pendingUndo).isNull(); assertThat(signalled.undoState).isNull();
        assertThatThrownBy(() -> act(signalled, "p1", "ACCEPT_UNDO", Map.of())).isInstanceOf(RuleViolation.class);
        d.hands.put("p0", new ArrayList<>(List.of(WhotCard.parse("circle-2"))));
        var qualified = act(d.build(), "p0", "PLAY", Map.of("card", "circle-2"));
        assertThat(qualified.qualifiedTeams).contains(0);
        assertThat(qualified.undoState).isNull();
        assertThatThrownBy(() -> act(qualified, "p0", "REQUEST_UNDO", Map.of())).isInstanceOf(RuleViolation.class);
    }

}
