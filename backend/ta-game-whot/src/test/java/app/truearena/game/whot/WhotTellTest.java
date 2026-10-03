package app.truearena.game.whot;

import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class WhotTellTest {
    private final WhotModule module = new WhotModule();
    private final WhotConfig config = new WhotConfig(60, 5, true, true, true,
            true, true, true, "tell");

    private WhotState start(int players) {
        List<String> ids = new ArrayList<>();
        for (int i = 0; i < players; i++) ids.add("p" + i);
        return (WhotState) module.initialState(ids, config, RandomSource.seeded(7));
    }

    private WhotState act(WhotState s, String actor, String type, Map<String, Object> data) {
        return (WhotState) module.onPlayerAction(s,
                new PlayerAction(UUID.randomUUID().toString(), actor, type, data));
    }

    private WhotState ready(int players) {
        WhotState s = start(players);
        String[] symbols = {"🪐", "🔮", "🛸", "🧿"};
        for (int i = 0; i < players; i++) {
            s = act(s, "p" + i, "CHOOSE_SIGNAL", Map.of("symbol", symbols[i / 2]));
        }
        assertThat(s.phase()).isEqualTo("Deal");
        return (WhotState) module.onPhaseElapsed(s, "Deal");
    }

    @Test
    void tellRequiresPairsAndKeepsSignalsPrivate() {
        assertThatThrownBy(() -> start(5)).isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "BAD_PLAYER_COUNT");
        WhotState s = start(4);
        assertThat(s.phase()).isEqualTo("Signals");
        s = act(s, "p0", "CHOOSE_SIGNAL", Map.of("symbol", "🪐"));
        assertThat(module.visibleStateFor(s, "p1").data()).containsEntry("yourSignal", "🪐");
        assertThat(module.visibleStateFor(s, "p2").data()).containsEntry("yourSignal", "");
        assertThat(module.broadcastState(s).data()).doesNotContainKey("yourSignal");
    }

    @Test
    void aWholeHandValueSetCanBeInterceptedByTappingItsSignal() {
        WhotState.Draft d = new WhotState.Draft(ready(4));
        d.hands.put("p0", new ArrayList<>(List.of(
                WhotCard.parse("circle-3"), WhotCard.parse("star-3"), WhotCard.parse("triangle-3"))));
        WhotState s = act(d.build(), "p0", "SIGNAL", Map.of("symbol", "🪐"));
        long id = s.signalId;
        assertThat(s.events.get(s.events.size() - 1).payload()).doesNotContainKey("valid");

        WhotState won = act(s, "p2", "BUZZ", Map.of("signalId", id));
        assertThat(won.finished()).isTrue();
        assertThat(won.win.winningSide()).isEqualTo("team-1");
        assertThat(won.win.perPlayerOutcome()).containsEntry("p2", "won")
                .containsEntry("p3", "won");
        assertThat(act(won, "p1", "BUZZ", Map.of("signalId", id))).isSameAs(won);
    }

    @Test
    void tellRequiresEveryCardToMatchAndRespectsHostRule() {
        WhotState.Draft d = new WhotState.Draft(ready(4));
        d.hands.put("p0", new ArrayList<>(List.of(
                WhotCard.parse("circle-3"), WhotCard.parse("star-3"), WhotCard.parse("triangle-4"))));
        WhotState signal = act(d.build(), "p0", "SIGNAL", Map.of("symbol", "🪐"));
        assertThat(act(signal, "p1", "BUZZ", Map.of("signalId", signal.signalId)).win.winningSide())
                .isEqualTo("team-1");

        WhotConfig shapeOnly = new WhotConfig(60, 5, true, true, true, true, true, true,
                "tell", "shape", 2);
        d = new WhotState.Draft(ready(4));
        d.config = shapeOnly;
        d.hands.put("p0", new ArrayList<>(List.of(
                WhotCard.parse("circle-3"), WhotCard.parse("star-3"))));
        signal = act(d.build(), "p0", "SIGNAL", Map.of("symbol", "🪐"));
        assertThat(act(signal, "p1", "BUZZ", Map.of("signalId", signal.signalId)).win.winningSide())
                .isEqualTo("team-1");

        d.hands.put("p0", new ArrayList<>(List.of(
                WhotCard.parse("circle-3"), WhotCard.parse("circle-4"))));
        signal = act(d.build(), "p0", "SIGNAL", Map.of("symbol", "🪐"));
        assertThat(act(signal, "p1", "BUZZ", Map.of("signalId", signal.signalId)).win.winningSide())
                .isEqualTo("team-0");
    }

    @Test
    void invalidStartingTellIsRedealtBeforePlay() {
        WhotState s = start(4);
        for (int i = 0; i < 4; i++) {
            s = act(s, "p" + i, "CHOOSE_SIGNAL", Map.of("symbol", i < 2 ? "🪐" : "🔮"));
        }
        s = act(s, "p0", "DEAL", Map.of("rounds", 3));
        WhotState.Draft d = new WhotState.Draft(s);
        d.market.addAll(d.hands.get("p0"));
        d.hands.put("p0", new ArrayList<>());
        int matchValue = d.market.stream().map(WhotCard::number)
                .filter(number -> d.market.stream().filter(card -> card.number() == number).count() >= 3)
                .findFirst().orElseThrow();
        List<WhotCard> matching = d.market.stream().filter(card -> card.number() == matchValue)
                .limit(3).toList();
        for (WhotCard card : matching) {
            assertThat(d.market.remove(card)).isTrue();
            d.hands.get("p0").add(card);
        }
        WhotState started = act(d.build(), "p0", "START", Map.of());
        assertThat(started.phase()).isEqualTo("Turn");
        assertThat(started.hands.get("p0").stream().map(WhotCard::number).distinct().count()).isGreaterThan(1);
        assertThat(started.events.stream().anyMatch(event -> event.type().equals("DEAL_RESHUFFLED"))).isTrue();
    }

    @Test
    void aDecoyBuzzEliminatesTheCallingTeam() {
        WhotState s = act(ready(4), "p0", "SIGNAL", Map.of("symbol", "🌌"));
        WhotState after = act(s, "p2", "BUZZ", Map.of("signalId", s.signalId));
        assertThat(after.eliminatedTeams).containsExactly(1);
        assertThat(after.win.winningSide()).isEqualTo("team-0");
    }

    @Test
    void teammateBuzzWithoutSetEliminatesTheirOwnTeam() {
        WhotState.Draft d = new WhotState.Draft(ready(4));
        d.hands.put("p0", new ArrayList<>(List.of(WhotCard.parse("circle-3"))));
        WhotState s = act(d.build(), "p0", "SIGNAL", Map.of("symbol", "🪐"));
        WhotState after = act(s, "p1", "BUZZ", Map.of("signalId", s.signalId));
        assertThat(after.eliminatedTeams).containsExactly(0);
        assertThat(after.win.winningSide()).isEqualTo("team-1");
    }

    @Test
    void twoNormalWhotTeamWinsStartAFreshFinal() {
        WhotState.Draft d = new WhotState.Draft(ready(6));
        d.pile = new ArrayList<>(List.of(WhotCard.parse("circle-7")));
        d.hands.put("p0", new ArrayList<>(List.of(WhotCard.parse("circle-3"))));
        d.hands.put("p2", new ArrayList<>(List.of(WhotCard.parse("circle-4"))));
        WhotState first = act(d.build(), "p0", "PLAY", Map.of("card", "circle-3"));
        assertThat(first.qualifiedTeams).containsExactly(0);
        assertThat(first.currentPlayer()).isEqualTo("p2");

        WhotState finale = act(first, "p2", "PLAY", Map.of("card", "circle-4"));
        assertThat(finale.stage).isEqualTo("final");
        assertThat(finale.phase()).isEqualTo("Signals");
        assertThat(finale.eliminatedTeams).contains(2);
        assertThat(finale.market).hasSize(54);
        assertThat(finale.pile).isEmpty();
        assertThat(finale.hands.values()).allSatisfy(hand -> assertThat(hand).isEmpty());
        assertThat(finale.teamSignals).isEmpty();
    }
}
