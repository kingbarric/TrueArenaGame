package app.truearena.api.bot;

import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.game.whot.WhotConfig;
import app.truearena.game.whot.WhotModule;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class WhotTellBotAdapterTest {
    private Map<String, Object> view(String phase) {
        var v = new LinkedHashMap<String, Object>();
        v.put("mode", "tell"); v.put("phase", phase); v.put("stage", "final");
        v.put("players", List.of("bot", "partner", "a", "b"));
        v.put("teams", List.of(List.of("bot", "partner"), List.of("a", "b")));
        v.put("qualifiedTeams", List.of()); v.put("eliminatedTeams", List.of());
        v.put("yourTeam", 0); v.put("yourSignal", "🪐"); v.put("yourSignalConfirmed", true);
        v.put("turnPlayer", "a"); v.put("topCard", "circle-5"); v.put("activeShape", "circle");
        v.put("yourHand", List.of("circle-3", "circle-7", "triangle-2"));
        v.put("handSizes", Map.of("bot", 3, "partner", 3, "a", 3, "b", 3));
        v.put("rules", Map.of("tellRule", "either", "tellMinCards", 3));
        return v;
    }

    private void see(WhotBotAdapter bot, Map<String, Object> view) {
        bot.onFrame("SNAPSHOT", view, "bot", Difficulty.HARD);
    }

    @Test void proposesOnceAndConfirmsThePartnersChosenSymbolWithoutOverwritingIt() {
        var bot = new WhotBotAdapter();
        var v = view("Signals"); v.put("yourSignal", ""); v.put("yourSignalConfirmed", false);
        see(bot, v);
        var proposal = bot.decideLocally("bot", Difficulty.EASY).orElseThrow();
        assertThat(proposal.type()).isEqualTo("CHOOSE_SIGNAL");
        assertThat(proposal.data().get("symbol")).isNotEqualTo("");
        v.put("yourSignal", "🧿");
        see(bot, v);
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().data()).containsEntry("symbol", "🧿");
        v.put("yourSignalConfirmed", true); see(bot, v);
        assertThat(bot.decideLocally("bot", Difficulty.HARD)).isEmpty();

        v.put("teams", List.of(List.of("partner", "bot"), List.of("a", "b")));
        v.put("yourSignal", ""); v.put("yourSignalConfirmed", false); see(bot, v);
        assertThat(bot.decideLocally("bot", Difficulty.HARD)).isEmpty();
        v.put("yourSignal", "🔮"); see(bot, v);
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().data()).containsEntry("symbol", "🔮");
    }

    @Test void sendsAValidTellOffTurnOnceAndHonoursTheHostsRuleAndMinimum() {
        var bot = new WhotBotAdapter(); var v = view("Turn");
        v.put("yourHand", List.of("circle-3", "circle-7", "circle-8"));
        assertThat(bot.onFrame("SNAPSHOT", v, "bot", Difficulty.HARD)).isPresent();
        var signal = bot.decideLocally("bot", Difficulty.HARD).orElseThrow();
        assertThat(signal.type()).isEqualTo("SIGNAL");
        assertThat(signal.data()).containsEntry("symbol", "🪐");
        see(bot, v); assertThat(bot.decideLocally("bot", Difficulty.HARD)).isEmpty();

        bot = new WhotBotAdapter(); v.put("rules", Map.of("tellRule", "value", "tellMinCards", 3));
        see(bot, v); assertThat(bot.decideLocally("bot", Difficulty.HARD)).isEmpty();
        v.put("yourHand", List.of("circle-3", "triangle-3", "star-3"));
        see(bot, v); assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().type()).isEqualTo("SIGNAL");
        bot = new WhotBotAdapter(); v.put("rules", Map.of("tellRule", "either", "tellMinCards", 4));
        see(bot, v); assertThat(bot.decideLocally("bot", Difficulty.HARD)).isEmpty();
    }

    @Test void buzzesItsTeammatesAgreedSignalOffTurnWithoutInspectingTheirCards() {
        var bot = new WhotBotAdapter(); var v = view("Waiting");
        v.put("signal", Map.of("id", 42L, "by", "partner", "symbol", "🪐", "sentAtMs", System.currentTimeMillis()));
        // These fields are deliberately not part of a player's information.
        v.put("hands", Map.of("partner", List.of("star-1"))); v.put("signalValid", false);
        assertThat(bot.onFrame("SNAPSHOT", v, "bot", Difficulty.HARD)).isPresent();
        var buzz = bot.decideLocally("bot", Difficulty.HARD).orElseThrow();
        assertThat(buzz.type()).isEqualTo("BUZZ"); assertThat(buzz.data()).containsEntry("signalId", 42L);
        see(bot, v); assertThat(bot.decideLocally("bot", Difficulty.HARD)).isEmpty();
    }

    @Test void ignoresDecoysOpponentsExpiredSignalsAndObviousTooSmallHands() {
        for (String sender : List.of("partner", "a", "bot")) {
            for (String symbol : List.of("🪐", "🔮")) {
                var bot = new WhotBotAdapter(); var v = view("Turn");
                v.put("signal", Map.of("id", 1, "by", sender, "symbol", symbol, "sentAtMs", System.currentTimeMillis()));
                see(bot, v);
                assertThat(bot.decideLocally("bot", Difficulty.HARD).isPresent()).isEqualTo(sender.equals("partner") && symbol.equals("🪐"));
            }
        }
        for (boolean expired : List.of(false, true)) {
            var bot = new WhotBotAdapter(); var v = view("Turn");
            v.put("signal", Map.of("id", 2, "by", "partner", "symbol", "🪐", "sentAtMs", System.currentTimeMillis() - (expired ? 4000 : 0)));
            if (!expired) v.put("handSizes", Map.of("partner", 2));
            see(bot, v); assertThat(bot.decideLocally("bot", Difficulty.HARD)).isEmpty();
        }
    }

    @Test void pausedQualifiedAndEliminatedBotsCannotSignalOrPlay() {
        for (String flag : List.of("paused", "qualifiedTeams", "eliminatedTeams")) {
            var bot = new WhotBotAdapter(); var v = view("Turn");
            v.put("turnPlayer", "bot"); v.put("yourHand", List.of("circle-3", "circle-7", "circle-8"));
            v.put(flag, flag.equals("paused") ? true : List.of(0));
            assertThat(bot.onFrame("SNAPSHOT", v, "bot", Difficulty.HARD)).isEmpty();
            assertThat(bot.decideLocally("bot", Difficulty.HARD)).isEmpty();
            assertThat(bot.fallbackAction("bot")).isEmpty();
        }
    }

    @Test void aFreshFinalRequiresFreshSignalConfirmation() {
        var bot = new WhotBotAdapter(); var v = view("Turn"); see(bot, v);
        v.put("phase", "Signals"); v.put("yourSignal", ""); v.put("yourSignalConfirmed", false);
        assertThat(bot.onFrame("SNAPSHOT", v, "bot", Difficulty.HARD)).isPresent();
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().type()).isEqualTo("CHOOSE_SIGNAL");
    }

    @Test void fourSixAndEightAgentTablesCompleteThroughSignalsQualificationAndFinals() {
        var game = new WhotModule();
        for (int count : List.of(4, 6, 8)) {
            List<String> players = new ArrayList<>(); var bots = new HashMap<String, WhotBotAdapter>();
            for (int i = 0; i < count; i++) { players.add("p" + i); bots.put("p" + i, new WhotBotAdapter()); }
            WhotConfig config = new WhotConfig(60, 5, true, true, true, true, true, true, "tell");
            GameState state = game.initialState(players, config, RandomSource.seeded(count));
            boolean sawFinal = count == 4;
            for (int step = 0; step < 700 && !state.finished(); step++) {
                if (state.phase().equals("Deal")) state = game.onPhaseElapsed(state, "Deal");
                for (String player : players) {
                    if (state.finished()) break;
                    var bot = bots.get(player);
                    var view = game.visibleStateFor(state, player).data();
                    sawFinal |= "final".equals(view.get("stage"));
                    if (bot.onFrame("SNAPSHOT", view, player, Difficulty.EASY).isPresent()) {
                        PlayerAction action = bot.decideLocally(player, Difficulty.EASY).orElseThrow();
                        state = game.onPlayerAction(state, action);
                    }
                }
            }
            assertThat(state.finished()).as("%s seats completed", count).isTrue();
            assertThat(sawFinal).as("%s seats reached final", count).isTrue();
            assertThat(game.checkWinCondition(state).orElseThrow().perPlayerOutcome().values())
                    .filteredOn("won"::equals).hasSize(2);
        }
    }
    @Test void agentsAcceptATakeBackOnceAndWaitForTheRemainingHumanVotes() {
        var bot = new WhotBotAdapter(); var v = view("Turn"); v.put("turnPlayer", "bot");
        v.put("pendingUndo", "partner"); v.put("undoResponders", List.of("bot", "a", "b")); v.put("undoAccepted", List.of());
        assertThat(bot.onFrame("SNAPSHOT", v, "bot", Difficulty.HARD)).isPresent();
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().type()).isEqualTo("ACCEPT_UNDO");
        v.put("undoAccepted", List.of("bot"));
        assertThat(bot.onFrame("SNAPSHOT", v, "bot", Difficulty.HARD)).isEmpty();
        assertThat(bot.decideLocally("bot", Difficulty.HARD)).isEmpty();
    }

}
