package app.truearena.api.bot;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import app.truearena.engine.WinResult;
import app.truearena.game.truearena.Presets;
import app.truearena.game.truearena.TrueArenaModule;
import org.junit.jupiter.api.Test;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Random;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A table of Cyber Agents playing whole games through the real rules — every seat an
 * agent, every frame (and every line of talk) as the server would carry it — with and
 * without the dynamics (docs/TRAITORS_DYNAMICS_PLAN.md).
 *
 * <p>It guards that every mode plays to an end with agents in every seat. The win
 * rates it prints are not the game's balance: agents read the vote record, remember
 * who vouched for whom and rally behind one name, but they can't read people, so the
 * Traitors still win most all-agent games (about 55–75%, from 85–99% before agents
 * did any of that). Read them only for which way a twist pushes.
 */
class TraitorsBalanceSimulationTest {

    private static final int GAMES = 150;
    private static final List<String> NAMES = List.of("Ada", "Bola", "Chidi", "Dayo", "Efe", "Femi", "Gozie", "Halima",
            "Ike", "Jumoke", "Kemi", "Lola", "Musa", "Nneka", "Obi", "Pele");

    /** Each mode's twists before the dynamics. */
    private static final Map<String, Map<String, Map<String, Object>>> BEFORE = Map.of(
            "classic_conspiracy", Map.of(),
            "midnight_heist", Map.of("poisoned_gift", Map.of("uses", 1, "announceClaim", true, "hideClaimant", true),
                    "immunity_coin", Map.of()),
            "blood_moon", Map.of(),
            "the_last_alibi", Map.of(),
            "final_gambit", Map.of("secret_accusation", Map.of("defenseSeconds", 60)));

    private static GameConfig withTwists(GameConfig b, Map<String, Map<String, Object>> twists) {
        return new GameConfig(b.catalogVersion(), b.preset(), b.table(), b.timers(), b.nightKill(), b.revealOnElimination(),
                b.tieBreak(), b.secondTie(), b.suddenDeathSeconds(), b.afk(), b.voteReveal(), b.endgameVeil(), twists);
    }

    record Outcome(String side, int rounds) {
    }

    /** One game, every seat a Cyber Agent, driven frame by frame like the server would. */
    static Outcome play(GameConfig config, int players, long seed) {
        TrueArenaModule module = new TrueArenaModule();
        List<String> ids = new ArrayList<>();
        for (int i = 1; i <= players; i++) ids.add("agent-" + i);
        GameState state = module.initialState(ids, config, RandomSource.seeded(seed));
        Map<String, TrueArenaBotAdapter> agents = new LinkedHashMap<>();
        Map<String, Deque<Map<String, Object>>> inbox = new HashMap<>();
        for (int i = 0; i < ids.size(); i++) {
            agents.put(ids.get(i), new TrueArenaBotAdapter(new Random(seed * 31 + i)));
            inbox.put(ids.get(i), new ArrayDeque<>());
        }
        Map<String, String> names = new HashMap<>();
        for (int i = 0; i < ids.size(); i++) names.put(ids.get(i), NAMES.get(i % NAMES.size()));
        agents.values().forEach(a -> a.playerNames(names));
        deliver(module, state, null, state.events(), ids, inbox);
        Random order = new Random(seed);
        for (int guard = 0; !state.finished() && guard < 4000; guard++) {
            boolean acted = false;
            List<String> turn = new ArrayList<>(ids);
            Collections.shuffle(turn, order);
            for (String id : turn) {
                TrueArenaBotAdapter agent = agents.get(id);
                boolean asked = false;
                for (Map<String, Object> frame; (frame = inbox.get(id).poll()) != null; ) {
                    @SuppressWarnings("unchecked") Map<String, Object> payload = (Map<String, Object>) frame.get("payload");
                    Optional<GameBotAdapter.BotPrompt> prompt = agent.onFrame((String) frame.get("type"), payload, id, Difficulty.MEDIUM);
                    asked |= prompt.isPresent() && !prompt.get().speak();
                    // What an agent says reaches the table (or the Traitors) as chat, as it would live.
                    if (prompt.isPresent() && prompt.get().speak() && prompt.get().fallback() != null) {
                        say(state, module, id, prompt.get().channel(), prompt.get().fallback(), ids, inbox);
                    }
                }
                if (!asked) continue;
                Optional<PlayerAction> move = agent.decideLocally(id, Difficulty.MEDIUM);
                if (move.isEmpty() || "CHAT_SEND".equals(move.get().type())) continue;
                GameState before = state;
                try {
                    state = module.onPlayerAction(state, move.get());
                } catch (RuleViolation refused) {
                    continue;
                }
                deliver(module, state, before, module.drainEvents(before, state), ids, inbox);
                acted = true;
                break;
            }
            if (!acted) {
                GameState before = state;
                state = module.onPhaseElapsed(state, state.phase());
                deliver(module, state, before, module.drainEvents(before, state), ids, inbox);
            }
        }
        String side = module.checkWinCondition(state).map(WinResult::winningSide).orElse("unfinished");
        return new Outcome(side, state.round());
    }

    private static void say(GameState state, TrueArenaModule module, String from, String channel, String text,
                            List<String> ids, Map<String, Deque<Map<String, Object>>> inbox) {
        for (String id : ids) {
            if (id.equals(from)) continue;
            String role = String.valueOf(module.visibleStateFor(state, id).data().get("yourRole"));
            if ("traitors".equals(channel) && !role.contains("traitor")) continue;
            inbox.get(id).add(Map.of("type", "EVENT", "payload", Map.of("type", "CHAT_MESSAGE",
                    "data", Map.of("from", from, "channel", channel == null ? "table" : channel, "text", text))));
        }
    }

    /** What each seat's connection would carry: the phase, the events it may see, then its own snapshot. */
    private static void deliver(TrueArenaModule module, GameState state, GameState before, List<GameEvent> events,
                                List<String> ids, Map<String, Deque<Map<String, Object>>> inbox) {
        for (String id : ids) {
            Map<String, Object> view = new HashMap<>(module.visibleStateFor(state, id).data());
            String role = String.valueOf(view.get("yourRole"));
            Deque<Map<String, Object>> q = inbox.get(id);
            if (before == null || !before.phase().equals(state.phase()) || before.round() != state.round()) {
                q.add(Map.of("type", "PHASE", "payload", Map.of("phase", state.phase(), "round", state.round())));
            }
            for (GameEvent e : events) {
                GameEvent.Visibility v = e.visibility();
                boolean sees = v.isPublic()
                        || "player".equals(v.scope()) && id.equals(v.key())
                        || "role".equals(v.scope()) && (role.equals(v.key()) || "traitor".equals(v.key()) && "recruited_traitor".equals(role));
                if (sees) q.add(Map.of("type", "EVENT", "payload", Map.of("type", e.type(), "data", e.payload())));
            }
            view.put("botPlayerIds", ids);
            q.add(Map.of("type", "SNAPSHOT", "payload", view));
        }
    }

    private static double traitorRate(List<Outcome> games) {
        return games.stream().filter(g -> "traitors".equals(g.side())).count() / (double) games.size();
    }

    @Test void everyModePlaysToAnEndWithAgentsInEverySeat() {
        StringBuilder report = new StringBuilder("\nTraitors win rate, all-agent tables (" + GAMES + " games each):\n");
        report.append(String.format("%-20s %8s %8s %8s%n", "mode", "before", "after", "rounds"));
        Map<String, Double> after = new LinkedHashMap<>();
        for (Presets.Mode mode : Presets.ALL) {
            int players = mode.config().table().players();
            List<Outcome> was = new ArrayList<>(), now = new ArrayList<>();
            for (long seed = 1; seed <= GAMES; seed++) {
                was.add(play(withTwists(mode.config(), BEFORE.get(mode.slug())), players, seed));
                now.add(play(mode.config(), players, seed));
            }
            assertThat(now).as("%s: every game ends", mode.slug()).allMatch(g -> !g.side().equals("unfinished"));
            assertThat(was).allMatch(g -> !g.side().equals("unfinished"));
            after.put(mode.slug(), traitorRate(now));
            report.append(String.format("%-20s %7.0f%% %7.0f%% %8.1f%n", mode.slug(), traitorRate(was) * 100,
                    traitorRate(now) * 100, now.stream().mapToInt(Outcome::rounds).average().orElse(0)));
        }
        System.out.println(report);
        assertThat(after).hasSize(Presets.ALL.size());
    }
}
