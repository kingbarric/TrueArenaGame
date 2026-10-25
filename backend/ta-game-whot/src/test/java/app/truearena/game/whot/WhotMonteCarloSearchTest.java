package app.truearena.game.whot;

import app.truearena.engine.*;
import org.junit.jupiter.api.Test;

import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;

class WhotMonteCarloSearchTest {
    private final WhotModule game = new WhotModule();
    private final WhotMonteCarloSearch.Limits generous = new WhotMonteCarloSearch.Limits(16, 12, 12000, 1000);

    private WhotState table(WhotConfig config, List<String> mine, List<String> other, String top, int copies) {
        var draft = new WhotState.Draft();
        draft.players = new ArrayList<>(List.of("bot", "other")); draft.config = config;
        draft.hands.put("bot", new ArrayList<>(mine.stream().map(WhotCard::parse).toList()));
        draft.hands.put("other", new ArrayList<>(other.stream().map(WhotCard::parse).toList()));
        draft.pile.add(WhotCard.parse(top));
        for (int i = 0; i < copies; i++) draft.market.addAll(WhotModule.singleDeck(config));
        for (List<WhotCard> hand : draft.hands.values()) for (WhotCard card : hand) assertThat(draft.market.remove(card)).isTrue();
        assertThat(draft.market.remove(draft.pile.getFirst())).isTrue();
        return draft.build();
    }

    private WhotMonteCarloSearch.Observation observation(WhotState state, List<String> known) {
        return WhotMonteCarloSearch.Observation.fromView(game.visibleStateFor(state, "bot").data(), known, "bot").orElseThrow();
    }

    @Test void samplesConserveMultipleDecksAndExcludeOnlyKnownCardsWithTheirMultiplicity() {
        WhotConfig config = new WhotConfig(60, 5, true, true, true, true, true, true);
        WhotState state = table(config, List.of("circle-1", "circle-1", "whot-20"), List.of("star-2", "cross-3"), "circle-5", 2);
        var observation = observation(state, List.of("circle-5"));
        List<WhotCard> unknown = WhotMonteCarloSearch.unknownCards(observation);
        assertThat(unknown).doesNotContain(WhotCard.parse("circle-1"));
        assertThat(Collections.frequency(unknown, WhotCard.parse("circle-5"))).isEqualTo(1);
        assertThat(Collections.frequency(unknown, WhotCard.parse("whot-20"))).isEqualTo(9);
        Set<List<WhotCard>> sampledHands = new HashSet<>();
        for (int seed = 0; seed < 8; seed++) {
            WhotState sample = WhotMonteCarloSearch.sample(observation, "bot", unknown, new Random(seed));
            assertThat(sample.handOf("bot")).isEqualTo(state.handOf("bot"));
            assertThat(sample.handOf("other")).hasSize(2);
            assertThat(sample.market).hasSize(state.market.size());
            assertThat(sample.topCard()).isEqualTo(state.topCard());
            List<WhotCard> complete = new ArrayList<>(sample.market);
            sample.hands.values().forEach(complete::addAll); complete.addAll(sample.pile);
            List<WhotCard> expected = new ArrayList<>(WhotModule.singleDeck(config)); expected.addAll(WhotModule.singleDeck(config));
            assertThat(complete).containsExactlyInAnyOrderElementsOf(expected);
            sampledHands.add(sample.handOf("other"));
        }
        assertThat(sampledHands).hasSizeGreaterThan(1);
    }

    @Test void incompleteReconnectHistorySamplesMissingDiscardsInsteadOfInventingKnownCards() {
        WhotState state = table(WhotConfig.defaults(), List.of("circle-1", "triangle-7"), List.of("star-2"), "circle-5", 1);
        var draft = new WhotState.Draft(state);
        draft.pile.add(0, draft.market.removeFirst());
        draft.pile.add(0, draft.market.removeFirst());
        state = draft.build();
        var observation = observation(state, List.of("circle-5"));
        WhotState sampled = WhotMonteCarloSearch.sample(observation, "bot", WhotMonteCarloSearch.unknownCards(observation), new Random(3));
        assertThat(sampled.pile).hasSize(3);
        assertThat(sampled.market).hasSize(state.market.size());
        assertThat(sampled.topCard().code()).isEqualTo("circle-5");
    }

    @Test void rolloutFindsTheHoldOnSequenceThatShedsBothCardsBeforeAnOpponentCanPlay() {
        WhotState state = table(WhotConfig.defaults(), List.of("circle-7", "circle-1"), List.of("circle-2"), "circle-5", 1);
        var result = WhotMonteCarloSearch.choose(observation(state, List.of("circle-5")), "bot", generous, new Random(7));
        assertThat(result.completedSamples()).isEqualTo(16);
        assertThat(result.transitions()).isGreaterThan(16);
        assertThat(result.action()).get().extracting(a -> a.data().get("card")).isEqualTo("circle-1");
        WhotState after = (WhotState) game.onPlayerAction(state, result.action().orElseThrow());
        assertThat(after.currentPlayer()).isEqualTo("bot");
        after = (WhotState) game.onPlayerAction(after, PlayerAction.of("bot", "PLAY", Map.of("card", "circle-7")));
        assertThat(after.finished()).isTrue();
        assertThat(after.win.winningSide()).isEqualTo("bot");
    }

    @Test void wildShapeIsPartOfTheSimulatedChoice() {
        WhotConfig config = new WhotConfig(60, 5, true, true, true, true, true, true);
        WhotState state = table(config, List.of("whot-20", "triangle-7"), List.of("circle-1"), "circle-5", 1);
        var result = WhotMonteCarloSearch.choose(observation(state, List.of("circle-5")), "bot", generous, new Random(4));
        assertThat(result.completedSamples()).isPositive();
        assertThat(result.action().orElseThrow().data()).containsEntry("card", "whot-20").containsEntry("shape", "triangle");
        game.onPlayerAction(state, result.action().orElseThrow());
    }

    @Test void rootActionsHonourPenaltyStackingAndDisabledSpecials() {
        for (boolean stacking : List.of(false, true)) {
            WhotConfig config = new WhotConfig(60, 5, true, true, stacking, false, false, false);
            WhotState state = table(config, List.of("circle-2", "whot-20"), List.of("circle-1"), "triangle-2", 1);
            var draft = new WhotState.Draft(state); draft.pendingPick = 4; state = draft.build();
            var result = WhotMonteCarloSearch.choose(observation(state, List.of("triangle-2")), "bot", generous, new Random(3));
            assertThat(result.action().orElseThrow().type()).isEqualTo(stacking ? "PLAY" : "DRAW");
            WhotState after = (WhotState) game.onPlayerAction(state, result.action().orElseThrow());
            assertThat(after.pendingPick).isEqualTo(stacking ? 6 : 0);
            if (!stacking) assertThat(after.handOf("bot")).hasSize(6);
        }
    }

    @Test void unrelatedPrivateFieldsCannotInfluenceAnObservationOrSeededDecision() {
        WhotState state = table(WhotConfig.defaults(), List.of("circle-1", "circle-7"), List.of("circle-2"), "circle-5", 1);
        Map<String, Object> view = new HashMap<>(game.visibleStateFor(state, "bot").data());
        var clean = WhotMonteCarloSearch.Observation.fromView(view, List.of("circle-5"), "bot").orElseThrow();
        view.put("hands", Map.of("other", List.of("circle-1")));
        view.put("market", List.of("circle-2")); view.put("seed", 9182);
        var injected = WhotMonteCarloSearch.Observation.fromView(view, List.of("circle-5"), "bot").orElseThrow();
        assertThat(injected).isEqualTo(clean);
        var a = WhotMonteCarloSearch.choose(clean, "bot", generous, new Random(11));
        var b = WhotMonteCarloSearch.choose(injected, "bot", generous, new Random(11));
        assertThat(a.action().orElseThrow().data()).isEqualTo(b.action().orElseThrow().data());
        assertThat(a.completedSamples()).isEqualTo(b.completedSamples());
    }

    @Test void exhaustedOrCancelledSearchStillHasALegalHeuristicWithoutPartialRolloutScores() {
        WhotState state = table(WhotConfig.defaults(), List.of("circle-1", "circle-7"), List.of("circle-2"), "circle-5", 1);
        var result = WhotMonteCarloSearch.choose(observation(state, List.of("circle-5")), "bot",
                new WhotMonteCarloSearch.Limits(128, 100, 1, 1000), new Random(3));
        assertThat(result.completedSamples()).isZero();
        assertThat(result.transitions()).isLessThanOrEqualTo(1);
        game.onPlayerAction(state, result.action().orElseThrow());
        Thread.currentThread().interrupt();
        try {
            result = WhotMonteCarloSearch.choose(observation(state, List.of("circle-5")), "bot", generous, new Random(3));
            assertThat(result.completedSamples()).isZero();
            assertThat(result.transitions()).isZero();
            assertThat(Thread.currentThread().isInterrupted()).isTrue();
        } finally { Thread.interrupted(); }
    }

    @Test void invalidCardCountsAndTheTellDoNotEnterClassicRollouts() {
        WhotState state = table(WhotConfig.defaults(), List.of("circle-1", "circle-7"), List.of("circle-2"), "circle-5", 1);
        Map<String, Object> view = new HashMap<>(game.visibleStateFor(state, "bot").data());
        view.put("mode", "tell");
        assertThat(WhotMonteCarloSearch.Observation.fromView(view, List.of("circle-5"), "bot")).isEmpty();
        view.put("mode", "classic"); view.put("marketLeft", 200);
        var o = WhotMonteCarloSearch.Observation.fromView(view, List.of("circle-5"), "bot").orElseThrow();
        assertThat(WhotMonteCarloSearch.choose(o, "bot", generous, new Random(1)).action()).isEmpty();
    }

    @Test void publicDiscardMemoryDoesNotDuplicateSnapshotsAndForgetsRecycledCards() {
        var memory = new WhotDiscardMemory();
        Map<String, Object> first = Map.of("discardCount", 3, "discardCards", List.of("circle-1", "circle-2", "circle-3"));
        memory.observe(first); memory.observe(first);
        memory.observe(Map.of("discardCount", 4, "discardCards", List.of("circle-2", "circle-3", "circle-4")));
        assertThat(memory.knownCards(0)).containsExactly("circle-1", "circle-2", "circle-3", "circle-4");
        assertThat(memory.knownCards(2)).containsExactly("circle-3", "circle-4");
        memory.reset(); // MARKET_RESHUFFLED also matters if the next pile has already grown beyond its old count.
        memory.observe(Map.of("discardCount", 5, "discardCards", List.of("star-1", "star-2", "star-3")));
        assertThat(memory.knownCards(0)).containsExactly("star-1", "star-2", "star-3");
        memory.observe(Map.of("discardCount", 1, "discardCards", List.of("star-4")));
        assertThat(memory.knownCards(0)).containsExactly("star-4");
    }
}
