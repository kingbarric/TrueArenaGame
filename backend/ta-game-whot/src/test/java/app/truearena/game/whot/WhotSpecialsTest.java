package app.truearena.game.whot;

import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The special cards, each of which is a switch on {@link WhotConfig} because
 * tables genuinely disagree about them.
 *
 * <p>Positions are built directly rather than played into, so each rule is
 * tested on its own — the same reasoning as the board games' hand-built
 * boards.
 */
class WhotSpecialsTest {

    private final WhotModule module = new WhotModule();
    private static final WhotCard.Shape CIRCLE = WhotCard.Shape.CIRCLE;
    private static final WhotCard.Shape TRIANGLE = WhotCard.Shape.TRIANGLE;

    /** A game mid-play: three players, chosen hands, a chosen card in play. */
    private WhotState table(WhotConfig config, WhotCard top, Map<String, List<WhotCard>> hands) {
        WhotState.Draft d = new WhotState.Draft();
        d.config = config;
        d.players = new ArrayList<>(hands.keySet());
        hands.forEach((k, v) -> d.hands.put(k, new ArrayList<>(v)));
        d.phase = "Turn";
        d.pile.add(top);
        // A market with something ordinary in it, so drawing is predictable.
        for (int i = 0; i < 40; i++) {
            d.market.add(new WhotCard(CIRCLE, 7));
        }
        return d.build();
    }

    private GameState play(GameState s, String actor, WhotCard card, String shape) {
        Map<String, Object> data = new java.util.LinkedHashMap<>();
        data.put("card", card.code());
        data.put("id", UUID.randomUUID().toString());
        if (shape != null) {
            data.put("shape", shape);
        }
        return module.onPlayerAction(s, PlayerAction.of(actor, "PLAY", data));
    }

    private GameState draw(GameState s, String actor) {
        return module.onPlayerAction(s, PlayerAction.of(actor, "DRAW",
                Map.of("id", UUID.randomUUID().toString())));
    }

    private String turnOf(GameState s) {
        return (String) module.broadcastState(s).data().get("turnPlayer");
    }

    private int pendingOf(GameState s) {
        return (int) module.broadcastState(s).data().get("pendingPick");
    }

    private Map<String, List<WhotCard>> threeHands(List<WhotCard> a, List<WhotCard> b, List<WhotCard> c) {
        Map<String, List<WhotCard>> hands = new java.util.LinkedHashMap<>();
        hands.put("a", a);
        hands.put("b", b);
        hands.put("c", c);
        return hands;
    }

    // ---------------------------------------------------------------- matching

    @Test
    void aCardMustMatchTheShapeOrTheNumber() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(TRIANGLE, 7), new WhotCard(CIRCLE, 11),
                        new WhotCard(TRIANGLE, 12)), List.of(), List.of()));

        assertThat(play(s, "a", new WhotCard(TRIANGLE, 7), null)).isNotNull();  // same number
        assertThat(play(s, "a", new WhotCard(CIRCLE, 11), null)).isNotNull();   // same shape
        assertThatThrownBy(() -> play(s, "a", new WhotCard(TRIANGLE, 12), null))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "DOESNT_MATCH");
    }

    @Test
    void youCannotPlayACardYouDontHold() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(CIRCLE, 3)), List.of(), List.of()));
        assertThatThrownBy(() -> play(s, "a", new WhotCard(CIRCLE, 11), null))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_IN_HAND");
    }

    // ---------------------------------------------------------------- 1 and 8

    @Test
    void oneHoldsYourTurnSoYouPlayAgain() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(CIRCLE, 1), new WhotCard(CIRCLE, 3)),
                        List.of(new WhotCard(CIRCLE, 5)), List.of(new WhotCard(CIRCLE, 8))));
        GameState after = play(s, "a", new WhotCard(CIRCLE, 1), null);
        assertThat(turnOf(after)).as("hold on keeps the turn").isEqualTo("a");
        assertThat(after.round()).as("hold on starts a fresh turn clock").isEqualTo(s.round() + 1);
    }

    @Test
    void eightSkipsTheNextPlayer() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(CIRCLE, 8), new WhotCard(CIRCLE, 3)),
                        List.of(new WhotCard(CIRCLE, 5)), List.of(new WhotCard(CIRCLE, 11))));
        GameState after = play(s, "a", new WhotCard(CIRCLE, 8), null);
        assertThat(turnOf(after)).as("b is suspended, so it falls to c").isEqualTo("c");
    }

    @Test
    void withTheSwitchesOffOneAndEightAreOrdinaryCards() {
        WhotConfig plain = new WhotConfig(45, 5, true, false, false, false, false, false);
        WhotState s = table(plain, new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(CIRCLE, 1), new WhotCard(CIRCLE, 8)),
                        List.of(new WhotCard(CIRCLE, 5)), List.of(new WhotCard(CIRCLE, 11))));
        assertThat(turnOf(play(s, "a", new WhotCard(CIRCLE, 1), null))).isEqualTo("b");
        assertThat(turnOf(play(s, "a", new WhotCard(CIRCLE, 8), null))).isEqualTo("b");
    }

    // ---------------------------------------------------------------- 2

    @Test
    void twoPutsTheNextPlayerTwoCardsInDebt() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(CIRCLE, 2), new WhotCard(CIRCLE, 3)),
                        List.of(new WhotCard(TRIANGLE, 11)), List.of()));
        GameState after = play(s, "a", new WhotCard(CIRCLE, 2), null);
        assertThat(pendingOf(after)).isEqualTo(2);
        assertThat(turnOf(after)).isEqualTo("b");
    }

    @Test
    void facingAPickTwoYouEitherStackOrDraw() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(CIRCLE, 2), new WhotCard(CIRCLE, 3)),
                        List.of(new WhotCard(TRIANGLE, 2), new WhotCard(TRIANGLE, 11)), List.of()));
        GameState owed = play(s, "a", new WhotCard(CIRCLE, 2), null);

        // An ordinary card won't do.
        assertThatThrownBy(() -> play(owed, "b", new WhotCard(TRIANGLE, 11), null))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "MUST_PICK");

        // Another 2 passes it on, and adds to it.
        GameState stacked = play(owed, "b", new WhotCard(TRIANGLE, 2), null);
        assertThat(pendingOf(stacked)).isEqualTo(4);
    }

    @Test
    void drawingClearsTheDebtAndTakesThatManyCards() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(CIRCLE, 2), new WhotCard(CIRCLE, 3)),
                        List.of(new WhotCard(TRIANGLE, 11)), List.of()));
        GameState owed = play(s, "a", new WhotCard(CIRCLE, 2), null);
        GameState paid = draw(owed, "b");

        assertThat(pendingOf(paid)).isZero();
        Map<?, ?> sizes = (Map<?, ?>) module.broadcastState(paid).data().get("handSizes");
        assertThat(sizes.get("b")).as("one card held, two drawn").isEqualTo(3);
    }

    @Test
    void withStackingOffTheOnlyAnswerToATwoIsToDraw() {
        WhotConfig noStack = new WhotConfig(45, 5, true, true, false, true, true, true);
        WhotState s = table(noStack, new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(CIRCLE, 2), new WhotCard(CIRCLE, 3)),
                        List.of(new WhotCard(TRIANGLE, 2)), List.of()));
        GameState owed = play(s, "a", new WhotCard(CIRCLE, 2), null);
        assertThatThrownBy(() -> play(owed, "b", new WhotCard(TRIANGLE, 2), null))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "MUST_PICK");
    }

    // ---------------------------------------------------------------- 14 and whot

    @Test
    void fourteenSendsEveryoneElseToTheMarket() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(CIRCLE, 14), new WhotCard(CIRCLE, 3)),
                        List.of(new WhotCard(TRIANGLE, 11)), List.of(new WhotCard(TRIANGLE, 12))));
        GameState after = play(s, "a", new WhotCard(CIRCLE, 14), null);

        Map<?, ?> sizes = (Map<?, ?>) module.broadcastState(after).data().get("handSizes");
        assertThat(sizes.get("a")).as("the player who dealt it draws nothing").isEqualTo(1);
        assertThat(sizes.get("b")).isEqualTo(2);
        assertThat(sizes.get("c")).isEqualTo(2);
        assertThat(turnOf(after)).as("the player who dealt it continues, not whoever went to market")
                .isEqualTo("a");
        assertThat(after.round()).as("a fresh turn clock, like hold on").isEqualTo(s.round() + 1);
    }

    @Test
    void whotIsWildAndItsHolderNamesTheShape() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(WhotCard.Shape.WHOT, 20), new WhotCard(CIRCLE, 3)),
                        List.of(), List.of()));
        GameState after = play(s, "a", new WhotCard(WhotCard.Shape.WHOT, 20), "triangle");
        assertThat(module.broadcastState(after).data().get("activeShape")).isEqualTo("triangle");
    }

    @Test
    void aWhotWithoutACalledShapeIsRefused() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(WhotCard.Shape.WHOT, 20)), List.of(), List.of()));
        assertThatThrownBy(() -> play(s, "a", new WhotCard(WhotCard.Shape.WHOT, 20), null))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "SHAPE_REQUIRED");
    }

    @Test
    void theCalledShapeIsWhatTheNextPlayerHasToMatch() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(WhotCard.Shape.WHOT, 20), new WhotCard(CIRCLE, 3)),
                        List.of(new WhotCard(TRIANGLE, 12), new WhotCard(CIRCLE, 11)), List.of()));
        GameState called = play(s, "a", new WhotCard(WhotCard.Shape.WHOT, 20), "triangle");

        assertThat(play(called, "b", new WhotCard(TRIANGLE, 12), null)).isNotNull();
        assertThatThrownBy(() -> play(called, "b", new WhotCard(CIRCLE, 11), null))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "DOESNT_MATCH");
    }

    // ---------------------------------------------------------------- winning

    @Test
    void sheddingYourLastCardWinsThere() {
        WhotState s = table(WhotConfig.defaults(), new WhotCard(CIRCLE, 7),
                threeHands(List.of(new WhotCard(CIRCLE, 11)),
                        List.of(new WhotCard(TRIANGLE, 12)), List.of(new WhotCard(TRIANGLE, 13))));
        GameState after = play(s, "a", new WhotCard(CIRCLE, 11), null);

        assertThat(after.finished()).isTrue();
        assertThat(module.visibleStateFor(after, "b").data().get("winner")).isEqualTo("a");
        assertThat(module.checkWinCondition(after)).get()
                .extracting(w -> w.perPlayerOutcome().get("a")).isEqualTo("won");
        assertThat(module.checkWinCondition(after)).get()
                .extracting(w -> w.perPlayerOutcome().get("b")).isEqualTo("lost");
    }
}
