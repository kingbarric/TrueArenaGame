package app.truearena.game.whot;

import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Whot's rules, including the deal, the specials, and the one thing that must
 * never leak: another player's hand.
 */
class WhotModuleTest {

    private final WhotModule module = new WhotModule();

    private static List<String> ids(int n) {
        List<String> out = new ArrayList<>(n);
        for (int i = 0; i < n; i++) {
            out.add("p" + i);
        }
        return out;
    }

    private GameState fresh(int players) {
        return module.initialState(ids(players), WhotConfig.defaults(), RandomSource.seeded(7));
    }

    private GameState act(GameState s, String actor, String type, Map<String, Object> data) {
        Map<String, Object> withId = new java.util.LinkedHashMap<>(data);
        withId.put("id", UUID.randomUUID().toString());
        return module.onPlayerAction(s, PlayerAction.of(actor, type, withId));
    }

    @SuppressWarnings("unchecked")
    private <T> T field(GameState s, String name) {
        try {
            Field f = WhotState.class.getDeclaredField(name);
            f.setAccessible(true);
            return (T) f.get(s);
        } catch (ReflectiveOperationException e) {
            throw new RuntimeException(e);
        }
    }

    /** Deals every player up to `cards` and starts the game. */
    private GameState dealAndStart(GameState s, int cards) {
        s = act(s, "p0", "DEAL", Map.of("rounds", cards));
        return act(s, "p0", "START", Map.of());
    }

    // ---------------------------------------------------------------- the deck

    @Test
    void aSingleDeckIsFiftyFourCardsWithTheWhots() {
        // includeWhot defaults to false now (plenty of tables leave them out) —
        // explicitly opt in, since this test is specifically about the with-Whots count.
        WhotConfig withWhot = new WhotConfig(60, 5, true, true, true, true, true, true);
        List<WhotCard> deck = WhotModule.singleDeck(withWhot);
        assertThat(deck).hasSize(54);
        assertThat(deck.stream().filter(WhotCard::isWhot)).hasSize(5);
    }

    @Test
    void leavingTheWhotsOutDropsTheDeckToFortyNine() {
        WhotConfig noWhot = new WhotConfig(45, 5, false, true, true, true, true, true);
        List<WhotCard> deck = WhotModule.singleDeck(noWhot);
        assertThat(deck).hasSize(49);
        assertThat(deck).noneMatch(WhotCard::isWhot);
    }

    @Test
    void theDeckHasNoSixAndNoNine() {
        // Upside down they're the same card, which is why they aren't printed.
        assertThat(WhotModule.singleDeck(WhotConfig.defaults()))
                .noneMatch(c -> c.number() == 6 || c.number() == 9);
    }

    @Test
    void aBigTableGetsMoreThanOneDeck() {
        WhotConfig c = new WhotConfig(60, 5, true, true, true, true, true, true);
        assertThat(WhotModule.buildDeck(c, 4)).hasSize(54);
        // Twenty players at five cards each is most of two decks before
        // anybody draws, so more get shuffled in.
        assertThat(WhotModule.buildDeck(c, 20).size()).isGreaterThan(20 * c.startingHand());
    }

    @Test
    void seatsTwoThroughTwenty() {
        assertThat(module.initialState(ids(2), WhotConfig.defaults(), RandomSource.seeded(1))).isNotNull();
        assertThat(module.initialState(ids(20), WhotConfig.defaults(), RandomSource.seeded(1))).isNotNull();
        assertThatThrownBy(() -> module.initialState(ids(1), WhotConfig.defaults(), RandomSource.seeded(1)))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "BAD_PLAYER_COUNT");
        assertThatThrownBy(() -> module.initialState(ids(21), WhotConfig.defaults(), RandomSource.seeded(1)))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "BAD_PLAYER_COUNT");
    }

    // ---------------------------------------------------------------- the deal

    @Test
    void theAutomaticDealStartsPlayWithinFiveSeconds() {
        assertThat(module.definePhases(WhotConfig.defaults()).stream()
                .filter(phase -> phase.name().equals("Deal"))
                .findFirst()
                .orElseThrow()
                .timerSeconds()).isEqualTo(5);
    }

    @Test
    void turnsWaitAtLeastSixtySecondsBeforePausing() {
        assertThat(WhotConfig.defaults().turnSeconds()).isEqualTo(60);
        WhotConfig olderRoom = new WhotConfig(15, 5, true, true, true, true, true, true);
        assertThat(module.definePhases(olderRoom).stream()
                .filter(phase -> phase.name().equals("Turn"))
                .findFirst().orElseThrow().timerSeconds()).isEqualTo(60);
        assertThat(module.definePhases(olderRoom).stream()
                .filter(phase -> phase.name().equals("Waiting"))
                .findFirst().orElseThrow().timerSeconds()).isEqualTo(60);
    }

    @Test
    void nothingIsDealtUntilTheDealerDealsIt() {
        GameState s = fresh(4);
        assertThat(s.phase()).isEqualTo("Deal");
        Map<String, List<WhotCard>> hands = field(s, "hands");
        assertThat(hands.values()).allSatisfy(h -> assertThat(h).isEmpty());
        assertThat((List<WhotCard>) field(s, "pile")).isEmpty();
    }

    @Test
    void oneTapDealsACardToEverybody() {
        GameState s = act(fresh(4), "p0", "DEAL", Map.of("rounds", 1));
        Map<String, List<WhotCard>> hands = field(s, "hands");
        assertThat(hands.values()).allSatisfy(h -> assertThat(h).hasSize(1));

        s = act(s, "p0", "DEAL", Map.of("rounds", 4));
        hands = field(s, "hands");
        assertThat(hands.values()).allSatisfy(h -> assertThat(h).hasSize(5));
    }

    @Test
    void onlyTheDealerTouchesTheCards() {
        GameState s = fresh(4);
        assertThatThrownBy(() -> act(s, "p2", "DEAL", Map.of("rounds", 1)))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_THE_DEALER");
        assertThatThrownBy(() -> act(s, "p2", "SHUFFLE", Map.of()))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_THE_DEALER");
    }

    @Test
    void shufflingMidDealTakesTheDealtCardsBackFirst() {
        GameState s = act(fresh(4), "p0", "DEAL", Map.of("rounds", 3));
        s = act(s, "p0", "SHUFFLE", Map.of());
        Map<String, List<WhotCard>> hands = field(s, "hands");
        assertThat(hands.values()).as("a reshuffle is a fresh start").allSatisfy(h -> assertThat(h).isEmpty());
    }

    @Test
    void theGameWontStartOnAnEmptyHand() {
        GameState s = act(fresh(4), "p0", "DEAL", Map.of("rounds", 1));
        assertThatThrownBy(() -> act(s, "p0", "START", Map.of()))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "DEAL_FIRST");
    }

    @Test
    void startingTurnsTheFirstCardOverAndOpensPlay() {
        GameState s = dealAndStart(fresh(4), 5);
        assertThat(s.phase()).isEqualTo("Turn");
        assertThat((List<WhotCard>) field(s, "pile")).isNotEmpty();
    }

    @Test
    void marketDrawsStayInOrderUntilTheLastCardThenShuffleDiscard() {
        WhotState.Draft d = new WhotState.Draft((WhotState) dealAndStart(fresh(2), 5));
        WhotCard first = WhotCard.parse("circle-3");
        WhotCard last = WhotCard.parse("star-7");
        WhotCard playedA = WhotCard.parse("square-4");
        WhotCard playedB = WhotCard.parse("triangle-5");
        WhotCard top = WhotCard.parse("cross-8");
        d.market = new ArrayList<>(List.of(first, last));
        d.pile = new ArrayList<>(List.of(playedA, playedB, top));
        d.turnIndex = 0;
        WhotState before = d.build();

        WhotState afterFirst = (WhotState) act(before, "p0", "DRAW", Map.of());
        assertThat(afterFirst.handOf("p0")).contains(last);
        assertThat(afterFirst.market).containsExactly(first);
        assertThat(afterFirst.events.stream().filter(e -> e.type().equals("MARKET_RESHUFFLED")))
                .isEmpty();

        WhotState afterLast = (WhotState) act(afterFirst, "p1", "DRAW", Map.of());
        assertThat(afterLast.handOf("p1")).contains(first);
        assertThat(afterLast.market).containsExactlyInAnyOrder(playedA, playedB);
        assertThat(afterLast.pile).containsExactly(top);
        assertThat(afterLast.events.stream().filter(e -> e.type().equals("MARKET_RESHUFFLED")))
                .hasSize(1);
        assertThat(module.broadcastState(afterLast).data())
                .containsEntry("marketLeft", 2).containsEntry("discardCount", 1)
                .containsEntry("discardCards", List.of(top.code()));

        WhotState afterRecycleDraw = (WhotState) act(afterLast, "p0", "DRAW", Map.of());
        assertThat(afterRecycleDraw.market).hasSize(1);
        assertThat(afterRecycleDraw.pile).containsExactly(top);
    }

    @Test
    void anIdleDealerDoesNotHoldTheTableUpForever() {
        GameState s = module.onPhaseElapsed(fresh(4), "Deal");
        assertThat(s.phase()).isEqualTo("Turn");
        Map<String, List<WhotCard>> hands = field(s, "hands");
        assertThat(hands.values()).allSatisfy(h -> assertThat(h).hasSize(5));
    }

    @Test
    void aTimedOutTurnPausesWithoutDrawingOrChangingPlayer() {
        GameState before = dealAndStart(fresh(4), 5);
        Map<String, List<WhotCard>> handsBefore = field(before, "hands");
        String playerBefore = String.valueOf(module.broadcastState(before).data().get("turnPlayer"));

        GameState waiting = module.onPhaseElapsed(before, "Turn");

        assertThat(waiting.phase()).isEqualTo("Waiting");
        assertThat(module.definePhases(WhotConfig.defaults()).stream()
                .filter(phase -> phase.name().equals("Waiting"))
                .findFirst().orElseThrow().startsPaused()).isTrue();
        assertThat((Map<String, List<WhotCard>>) field(waiting, "hands"))
                .isEqualTo(handsBefore);
        assertThat(String.valueOf(module.broadcastState(waiting).data().get("turnPlayer")))
                .isEqualTo(playerBefore);

        GameState afterDraw = act(waiting, playerBefore, "DRAW", Map.of());
        assertThat(afterDraw.phase()).isEqualTo("Turn");
        assertThat(String.valueOf(module.broadcastState(afterDraw).data().get("turnPlayer")))
                .isNotEqualTo(playerBefore);
    }

    @Test
    void cardsCannotBePlayedBeforeTheyAreDealt() {
        GameState s = fresh(4);
        assertThatThrownBy(() -> act(s, "p0", "DRAW", Map.of()))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "WRONG_PHASE");
    }

    @Test
    void aPlayerCanEndTheTableAndTheNextSeatWins() {
        GameState s = dealAndStart(fresh(3), 5);
        s = act(s, "p1", "FORFEIT", Map.of());

        assertThat(s.phase()).isEqualTo("Results");
        assertThat(module.checkWinCondition(s)).isPresent();
        assertThat(module.checkWinCondition(s).orElseThrow().winningSide()).isEqualTo("p2");
    }

    // ---------------------------------------------------------------- secrecy

    @Test
    void youSeeYourOwnHandAndNobodyElsesEver() {
        GameState s = dealAndStart(fresh(4), 5);

        Map<String, Object> mine = module.visibleStateFor(s, "p0").data();
        assertThat((List<?>) mine.get("yourHand")).hasSize(5);

        // Everyone's count is public; nobody's cards are.
        assertThat((Map<?, ?>) mine.get("handSizes")).hasSize(4);
        assertThat(mine).doesNotContainKey("hands");

        Map<String, Object> theirs = module.visibleStateFor(s, "p1").data();
        assertThat(theirs.get("yourHand")).isNotEqualTo(mine.get("yourHand"));

        Map<String, Object> spectator = module.broadcastState(s).data();
        assertThat(spectator).doesNotContainKey("yourHand");
        assertThat(spectator).doesNotContainKey("hands");
    }

    // ---------------------------------------------------------------- playersToAct (push turn reminders)

    @Test
    void playersToActIsWhoeverIsOnTurn() {
        WhotState s = (WhotState) fresh(3);
        assertThat(module.playersToAct(s)).containsExactly(s.currentPlayer());
    }
}
