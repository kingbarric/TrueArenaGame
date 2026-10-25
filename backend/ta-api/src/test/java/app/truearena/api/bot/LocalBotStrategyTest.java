package app.truearena.api.bot;

import app.truearena.engine.*;
import app.truearena.game.draughts.*;
import app.truearena.game.goosi.*;
import app.truearena.game.ludo.*;
import app.truearena.game.whot.*;
import org.junit.jupiter.api.Test;

import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;

class LocalBotStrategyTest {
    private void play(GameModule game, GameSettings settings, int steps) {
        GameState state = game.initialState(List.of("a", "b"), settings, RandomSource.seeded(42));
        if ("Deal".equals(state.phase())) state = game.onPhaseElapsed(state, "Deal");
        var factory = new GameBotAdapterFactory();
        Map<String, GameBotAdapter> bots = Map.of("a", factory.create(game.gameType()), "b", factory.create(game.gameType()));
        int played = 0;
        for (; played < steps && !state.finished(); played++) {
            String actor = game.playersToAct(state).iterator().next();
            GameBotAdapter bot = bots.get(actor);
            assertThat(bot.onFrame("SNAPSHOT", game.visibleStateFor(state, actor).data(), actor, Difficulty.EASY))
                    .as("%s step %s phase %s", game.gameType(), played, state.phase()).isPresent();
            PlayerAction action = bot.decideLocally(actor, Difficulty.EASY).orElseThrow();
            GameState next = game.onPlayerAction(state, action);
            assertThat(next).isNotSameAs(state);
            state = next;
        }
        assertThat(played).isPositive();
    }

    @Test void boardAndCardStrategiesPlayThroughRealRulesWithoutAModel() {
        play(new LudoModule(), LudoConfig.defaults(), 160);
        play(new WhotModule(), WhotConfig.defaults(), 100);
        play(new DraughtsModule(), new DraughtsConfig(60, false), 60);
        play(new DraughtsModule(), new DraughtsConfig(60, true), 60);
        play(new GoosiModule(), GoosiConfig.defaults(), 80);
        play(new GoosiModule(), new GoosiConfig(4, 45, "oware"), 80);
    }

    private void advancedPlay(GameModule game, GameSettings settings, List<String> players, Difficulty level, int steps) {
        GameState state = game.initialState(players, settings, RandomSource.seeded(77));
        if ("Deal".equals(state.phase())) state = game.onPhaseElapsed(state, "Deal");
        var factory = new GameBotAdapterFactory();
        Map<String, GameBotAdapter> bots = new HashMap<>();
        players.forEach(p -> bots.put(p, factory.create(game.gameType())));
        int played = 0;
        for (; played < steps && !state.finished(); played++) {
            String actor = game.playersToAct(state).iterator().next();
            GameBotAdapter bot = bots.get(actor);
            // All players receive private snapshots and public events, as they do in the runtime.
            for (String player : players) {
                var prompt = bots.get(player).onFrame("SNAPSHOT", game.visibleStateFor(state, player).data(), player, level);
                if (player.equals(actor)) assertThat(prompt).as("%s %s step %d", game.gameType(), level, played).isPresent();
            }
            PlayerAction action = bot.decideLocally(actor, level).orElseThrow();
            GameState next = game.onPlayerAction(state, action);
            assertThat(next).isNotSameAs(state);
            for (GameEvent event : game.drainEvents(state, next)) {
                if (event.visibility().isPublic()) for (String player : players)
                    bots.get(player).onFrame("EVENT", Map.of("type", event.type(), "data", event.payload()), player, level);
            }
            state = next;
        }
        assertThat(played).isGreaterThan(5);
    }

    @Test void proAndLegendCardRolloutsPlayThroughWildsDisabledSpecialsAndLargerTables() {
        for (Difficulty level : List.of(Difficulty.MEDIUM, Difficulty.HARD)) {
            advancedPlay(new WhotModule(), WhotConfig.defaults(), List.of("a", "b"), level, 40);
            advancedPlay(new WhotModule(), new WhotConfig(60, 5, true, false, false, false, false, false),
                    List.of("a", "b", "c", "d"), level, 40);
        }
    }

    @Test void proAndLegendDiceSearchPlaysThroughAllSeatLayoutsAndEightPieceGames() {
        for (Difficulty level : List.of(Difficulty.MEDIUM, Difficulty.HARD)) {
            advancedPlay(new LudoModule(), new LudoConfig(60, 8), List.of("a", "b"), level, 24);
            advancedPlay(new LudoModule(), LudoConfig.defaults(), List.of("a", "b", "c"), level, 24);
            advancedPlay(new LudoModule(), LudoConfig.defaults(), List.of("a", "b", "c", "d"), level, 24);
        }
    }

    @Test void hardLudoFinishesATokenInsteadOfTakingAMinorAdvance() {
        var bot = new LudoBotAdapter();
        bot.onFrame("SNAPSHOT", Map.of("phase", "Turn", "turnPlayer", "bot", "players", List.of("bot", "human"),
                "pieces", Map.of("bot", List.of(55, 10, -1, -1), "human", List.of(-1, -1, -1, -1)),
                "dice", List.of(1), "legalMoves", List.of(Map.of("token", 1, "die", 1), Map.of("token", 0, "die", 1))),
                "bot", Difficulty.HARD);
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().data()).containsEntry("token", 0);
    }

    @Test void hardWhotPreservesItsWildWhenItCanContinueItsStrongShape() {
        var bot = new WhotBotAdapter();
        bot.onFrame("SNAPSHOT", Map.of("phase", "Turn", "turnPlayer", "bot", "topCard", "circle-5",
                "activeShape", "circle", "yourHand", List.of("whot-20", "circle-7", "circle-10")), "bot", Difficulty.HARD);
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().data().get("card"))
                .isIn("circle-7", "circle-10");
    }

    @Test void wordBluffGuessesFromPublicCluesDespiteAnUnrelatedPrivateField() {
        var bot = new WordBluffBotAdapter();
        bot.onFrame("SNAPSHOT", Map.of("phase", "Turn", "textMode", true, "describer", "human",
                "yourWord", "volcano", "teamA", List.of("human", "bot"), "teamB", List.of("other", "judge")), "bot", Difficulty.HARD);
        bot.onFrame("EVENT", Map.of("type", "TEXT_CLUE", "data", Map.of("from", "human", "wordIndex", 1,
                "text", "Huge grey animal with a long trunk and tusks")), "bot", Difficulty.HARD);
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().data()).containsEntry("text", "elephant");
    }

    @Test void traitorsUsePublicEvidenceAndNeverTargetTheirOwnAlly() {
        var bot = new TrueArenaBotAdapter();
        bot.onFrame("SNAPSHOT", Map.of("phase", "RoundTable", "yourRole", "traitor", "fellowTraitors", List.of("ally"),
                "alive", List.of("bot", "ally", "suspect", "other")), "bot", Difficulty.HARD);
        bot.onFrame("EVENT", Map.of("type", "PUBLIC_ACCUSATION", "data", Map.of("by", "other", "accused", "suspect")), "bot", Difficulty.HARD);
        bot.onFrame("PHASE", Map.of("phase", "Vote"), "bot", Difficulty.HARD);
        bot.onFrame("EVENT", Map.of("type", "VOTE_OPEN", "data", Map.of()), "bot", Difficulty.HARD);
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().data()).containsEntry("target", "suspect");
        bot.onFrame("PHASE", Map.of("phase", "Night"), "bot", Difficulty.HARD);
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().data().get("target")).isIn("suspect", "other");
    }

    @Test void huudpolyRaisesCashInsteadOfVoluntarilyGoingBankrupt() {
        var bot = new MonopolyBotAdapter();
        bot.onFrame("SNAPSHOT", Map.of("phase", "Debt", "decisionPlayer", "bot", "legalActions", List.of(
                Map.of("action", "BANKRUPT", "data", Map.of()),
                Map.of("action", "MORTGAGE", "data", Map.of("property", 1)))), "bot", Difficulty.HARD);
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().type()).isEqualTo("MORTGAGE");
    }

    @Test void whotWaitsForTheUpdatedPrivateHandAndHonoursStackingRules() {
        var bot = new WhotBotAdapter();
        bot.onFrame("SNAPSHOT", Map.of("phase", "Turn", "turnPlayer", "human", "yourHand", List.of("circle-2")),
                "bot", Difficulty.HARD);
        assertThat(bot.onFrame("EVENT", Map.of("type", "TURN_STARTED", "data", Map.of("player", "bot")),
                "bot", Difficulty.HARD)).isEmpty();
        bot.onFrame("SNAPSHOT", Map.of("phase", "Turn", "turnPlayer", "bot", "pendingPick", 2,
                "yourHand", List.of("circle-2"), "rules", Map.of("pickTwo", true, "pickTwoStacking", false)),
                "bot", Difficulty.HARD);
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().type()).isEqualTo("DRAW");
    }

    @Test void rookieWordBluffNeedsMoreEvidenceWhileProCanMatchAShortClue() {
        for (Difficulty level : List.of(Difficulty.EASY, Difficulty.MEDIUM)) {
            var bot = new WordBluffBotAdapter();
            bot.onFrame("SNAPSHOT", Map.of("phase", "Turn", "textMode", true, "describer", "human",
                    "teamA", List.of("human", "bot"), "teamB", List.of("other", "judge")), "bot", level);
            bot.onFrame("EVENT", Map.of("type", "TEXT_CLUE", "data", Map.of("from", "human", "wordIndex", 1,
                    "text", "grey trunk")), "bot", level);
            var action = bot.decideLocally("bot", level).orElseThrow();
            if (level == Difficulty.EASY) assertThat(action.type()).isEqualTo("CHAT_SEND");
            else assertThat(action.data()).containsEntry("text", "elephant");
        }
    }

    @Test void legendWordBluffCombinesEarlierCluesThatProHasForgotten() {
        for (Difficulty level : List.of(Difficulty.MEDIUM, Difficulty.HARD)) {
            var bot = new WordBluffBotAdapter();
            bot.onFrame("SNAPSHOT", Map.of("phase", "Turn", "textMode", true, "describer", "human",
                    "teamA", List.of("human", "bot"), "teamB", List.of("other", "judge")), "bot", level);
            for (String clue : List.of("grey", "hmm", "trunk")) {
                bot.onFrame("EVENT", Map.of("type", "TEXT_CLUE", "data", Map.of("from", "human", "wordIndex", 1,
                        "text", clue)), "bot", level);
                if (!clue.equals("trunk")) bot.decideLocally("bot", level);
            }
            var action = bot.decideLocally("bot", level).orElseThrow();
            if (level == Difficulty.MEDIUM) assertThat(action.type()).isEqualTo("CHAT_SEND");
            else assertThat(action.data()).containsEntry("text", "elephant");
        }
    }

    @Test void legendTraitorsWeighsRevealedVotingEvidenceRatherThanOnlyAccusations() {
        var bot = new TrueArenaBotAdapter();
        bot.onFrame("SNAPSHOT", Map.of("phase", "RoundTable", "yourRole", "faithful",
                "alive", List.of("bot", "voter", "other", "eliminated")), "bot", Difficulty.HARD);
        bot.onFrame("EVENT", Map.of("type", "VOTE_REVEALED", "data", Map.of("voter", "voter", "target", "eliminated")), "bot", Difficulty.HARD);
        bot.onFrame("EVENT", Map.of("type", "PLAYER_ELIMINATED", "data", Map.of("id", "eliminated", "roleShown", true,
                "role", "traitor")), "bot", Difficulty.HARD);
        bot.onFrame("EVENT", Map.of("type", "PUBLIC_ACCUSATION", "data", Map.of("by", "other", "accused", "voter")), "bot", Difficulty.HARD);
        bot.onFrame("PHASE", Map.of("phase", "Vote"), "bot", Difficulty.HARD);
        assertThat(bot.decideLocally("bot", Difficulty.MEDIUM).orElseThrow().data()).containsEntry("target", "voter");
        assertThat(bot.decideLocally("bot", Difficulty.HARD).orElseThrow().data()).containsEntry("target", "other");
    }
}
