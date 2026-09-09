package app.truearena.game.truearena;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameRunner;
import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Deterministic auto-play: bots run a full game from a config so the engine can be
 * exercised end-to-end without the WebSocket transport. Same seed → same game.
 *
 * <p>Strategy: Traitors murder and vote the first living Faithful; Faithful vote a
 * pseudo-random living non-self. Enough to drive every phase and both win conditions.
 */
public final class AutoPlay {

    public record Result(
            String winningSide,
            int rounds,
            int players,
            Map<String, String> finalRoles,
            List<String> eliminated,
            List<Map<String, Object>> publicEvents) {
    }

    public static Result run(GameConfig config, int players, long seed) {
        TrueArenaModule module = new TrueArenaModule();
        GameRunner runner = new GameRunner(module);
        RandomSource voteRng = RandomSource.seeded(seed ^ 0x5DEECE66DL);

        List<String> ids = new ArrayList<>();
        for (int i = 1; i <= players; i++) {
            ids.add("p" + i);
        }

        GameState state = module.initialState(ids, config, RandomSource.seeded(seed));
        List<GameEvent> log = new ArrayList<>(state.events());

        int guard = 0;
        while (!state.finished() && guard++ < 400) {
            switch (state.phase()) {
                case "Night" -> state = playNight(runner, state, log);
                case "Vote" -> state = playVote(runner, state, log, voteRng);
                case "Results" -> {
                }
                default -> state = collect(runner.elapse(state, state.phase()), log);
            }
        }

        TruearenaState ts = (TruearenaState) state;
        List<Map<String, Object>> pub = new ArrayList<>();
        for (GameEvent e : log) {
            if (e.visibility().isPublic()) {
                pub.add(Map.of("seq", e.seq(), "type", e.type(), "payload", e.payload()));
            }
        }
        return new Result(
                ts.win == null ? "unfinished" : ts.win.winningSide(),
                ts.round, players, ts.roles, ts.eliminatedLog, pub);
    }

    private static GameState playNight(GameRunner runner, GameState state, List<GameEvent> log) {
        TruearenaState s = (TruearenaState) state;
        List<String> faithful = s.aliveFaithful();
        GameState cur = state;
        if (!faithful.isEmpty()) {
            String target = faithful.get(0);
            for (String traitor : s.aliveTraitors()) {
                if (!"Night".equals(cur.phase())) {
                    break;
                }
                cur = collect(runner.apply(cur, PlayerAction.of(traitor, "NIGHT_TARGET", Map.of("target", target))), log);
            }
        }
        if ("Night".equals(cur.phase())) {
            cur = collect(runner.elapse(cur, "Night"), log);
        }
        return cur;
    }

    private static GameState playVote(GameRunner runner, GameState state, List<GameEvent> log, RandomSource rng) {
        TruearenaState s = (TruearenaState) state;
        List<String> living = s.alive.stream().toList();
        List<String> faithful = s.aliveFaithful();
        GameState cur = state;
        for (String voter : living) {
            if (!"Vote".equals(cur.phase())) {
                break;
            }
            String target;
            if (s.isTraitor(voter) && !faithful.isEmpty() && !faithful.get(0).equals(voter)) {
                target = faithful.get(0);
            } else {
                List<String> opts = new ArrayList<>(living);
                opts.remove(voter);
                if (opts.isEmpty()) {
                    break;
                }
                target = opts.get(rng.nextInt(opts.size()));
            }
            cur = collect(runner.apply(cur, PlayerAction.of(voter, "CAST_VOTE", Map.of("target", target))), log);
        }
        if ("Vote".equals(cur.phase())) {
            cur = collect(runner.elapse(cur, "Vote"), log);
        }
        return cur;
    }

    private static GameState collect(GameRunner.Step step, List<GameEvent> log) {
        log.addAll(step.events());
        return step.state();
    }

    private AutoPlay() {
    }
}
