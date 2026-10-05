package app.truearena.game.goosi;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameModule;
import app.truearena.engine.GameSettings;
import app.truearena.engine.GameState;
import app.truearena.engine.Phase;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.PlayerVisibleState;
import app.truearena.engine.PublicBroadcastState;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import app.truearena.engine.WinResult;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * PlayHuud Macala has two rows of six houses and four seeds per house. Seeds
 * travel counter-clockwise around all twelve houses. If a drop makes any
 * house contain exactly four seeds, the mover collects those four at once.
 * When the last seed lands in an occupied house, the mover picks up that
 * house and continues; landing in an empty house ends the turn.
 */
public final class GoosiModule implements GameModule {

    public static final String GAME_TYPE = "goosi";

    @Override
    public String gameType() {
        return GAME_TYPE;
    }

    @Override
    public List<Phase> definePhases(GameSettings settings) {
        GoosiConfig config = (GoosiConfig) settings;
        List<Phase> phases = new ArrayList<>();
        for (int i = 0; i < 2; i++) {
            phases.add(new Phase("TurnP" + i, config.turnSeconds()));
            // Running out of time offers chances rather than playing for you
            // — each waits, paused, until somebody resumes. See onPhaseElapsed.
            phases.add(Phase.awaitingResume("GraceP" + i + "a", GRACE_SECONDS));
            phases.add(Phase.awaitingResume("GraceP" + i + "b", FINAL_GRACE_SECONDS));
        }
        phases.add(Phase.untimed("Results"));
        return phases;
    }

    // ---------------------------------------------------------------- setup

    @Override
    public GameState initialState(List<String> playerIds, GameSettings settings, RandomSource rng) {
        GoosiConfig config = (GoosiConfig) settings;
        int n = playerIds.size();
        if (n != 2) {
            throw new RuleViolation("NEEDS_TWO_PLAYERS", "Macala needs exactly 2 players — got " + n);
        }
        List<String> shuffled = new ArrayList<>(playerIds);
        rng.shuffle(shuffled);

        GoosiState.Draft d = new GoosiState.Draft();
        d.config = config;
        d.players = shuffled;
        d.scores = new int[n];
        int pitsPerPlayer = 6;
        for (int p = 0; p < n; p++) {
            for (int i = 0; i < pitsPerPlayer; i++) {
                d.owner[p * pitsPerPlayer + i] = shuffled.get(p);
            }
        }
        for (int i = 0; i < 12; i++) {
            d.pits[i] = config.seedsPerPit();
        }
        d.turnIndex = 0;
        d.phase = "TurnP0";
        d.round = 1;

        d.emit("GAME_STARTED", Map.of(
                "players", List.copyOf(shuffled),
                "pits", pitsSnapshot(d.pits),
                "owner", ownerSnapshot(d.owner),
                "legalPits", legalPits(d.pits, d.owner, shuffled.get(0)),
                "mode", config.mode(),
                "seedsPerPit", config.seedsPerPit(),
                "turnSeconds", config.turnSeconds()));
        return d.build();
    }

    // ---------------------------------------------------------------- actions

    @Override
    public GameState onPlayerAction(GameState state, PlayerAction action) {
        GoosiState s = (GoosiState) state;
        if (s.finished() || s.appliedActionIds.contains(action.actionId())) {
            return s;
        }
        GoosiState.Draft d = new GoosiState.Draft(s);
        d.appliedActionIds.add(action.actionId());

        switch (action.type()) {
            case "SOW" -> sowAction(d, s, action);
            case "RESIGN" -> resign(d, s, action.actor());
            default -> throw new RuleViolation("UNKNOWN_ACTION", "no handler for " + action.type());
        }
        return d.build();
    }

    private void resign(GoosiState.Draft d, GoosiState s, String actor) {
        int quitter = s.indexOf(actor);
        require(quitter >= 0, "NOT_A_PLAYER", "you're not one of the players in this game");
        forfeit(d, s, quitter);
        d.emit("PLAYER_RESIGNED", Map.of("player", actor));
    }

    /**
     * A clock running out no longer sows for you. It walks the same ladder
     * Draughts uses: the turn expiring pauses the room, resuming buys
     * {@value #GRACE_SECONDS} more seconds, that expiring pauses again, and
     * only the last {@value #FINAL_GRACE_SECONDS}-second chance running out
     * settles it. Each grace phase waits paused so the time isn't spent
     * while the player is still away.
     *
     * <p>Macala is head to head, so the player who runs out forfeits and the
     * other takes the game, exactly as in Draughts.
     */
    @Override
    public GameState onPhaseElapsed(GameState state, String endedPhase) {
        GoosiState s = (GoosiState) state;
        if (s.finished()) {
            return s;
        }
        GoosiState.Draft d = new GoosiState.Draft(s);
        int idx = s.turnIndex;

        String nextPhase = nextGracePhase(endedPhase, idx);
        if (nextPhase != null) {
            d.phase = nextPhase;
            boolean lastChance = nextPhase.endsWith("b");
            d.emit("TURN_GRACE", Map.of(
                    "player", s.players.get(idx),
                    "seconds", lastChance ? FINAL_GRACE_SECONDS : GRACE_SECONDS,
                    "lastChance", lastChance));
            return d.build();
        }

        if (s.players.size() == 2) {
            forfeit(d, s, idx);
        } else {
            d.emit("TURN_SKIPPED", Map.of("player", s.players.get(idx)));
            advanceTurn(d, s);
        }
        return d.build();
    }

    /** The next rung of the ladder, or null once the chances are used up. */
    private String nextGracePhase(String endedPhase, int turnIndex) {
        if (endedPhase.startsWith("TurnP")) {
            return "GraceP" + turnIndex + "a";
        }
        if (endedPhase.startsWith("GraceP") && endedPhase.endsWith("a")) {
            return "GraceP" + turnIndex + "b";
        }
        return null;
    }

    /** Head-to-head only: whoever ran out of chances loses, whatever the scores say. */
    private void forfeit(GoosiState.Draft d, GoosiState s, int quittingIndex) {
        int n = s.players.size();
        List<String> winners = new ArrayList<>();
        Map<String, String> outcome = new LinkedHashMap<>();
        for (int i = 0; i < n; i++) {
            String pid = s.players.get(i);
            boolean won = i != quittingIndex;
            if (won) {
                winners.add(pid);
            }
            outcome.put(pid, won ? "won" : "lost");
        }
        d.win = new WinResult(winners.get(0), outcome);
        d.phase = "Results";
        d.emit("GAME_OVER", Map.of(
                "winningSide", winners.get(0), "winners", winners,
                "scores", scoresSnapshot(s.players, d.scores)));
    }

    /** Seconds offered after a turn's clock runs out, once somebody resumes. */
    static final int GRACE_SECONDS = 20;

    /** Seconds on the final chance. */
    static final int FINAL_GRACE_SECONDS = 5;

    private void sowAction(GoosiState.Draft d, GoosiState s, PlayerAction a) {
        int myIndex = s.indexOf(a.actor());
        require(myIndex >= 0, "NOT_A_PLAYER", "you're not one of the players in this game");
        require(myIndex == s.turnIndex, "NOT_YOUR_TURN", "it's not your turn");

        int from = intField(a, "pit");
        require(from >= 0 && from < 12, "BAD_PIT", "house out of range");
        require(a.actor().equals(s.owner[from]), "NOT_YOUR_PIT", "that pit isn't yours");
        require(s.pits[from] > 0, "EMPTY_PIT", "that pit has no seeds to sow");
        if (GoosiConfig.OWARE.equals(s.config.mode())) {
            sowOware(d, s, a.actor(), myIndex, from);
        } else {
            sowRelay(d, s, a.actor(), myIndex, from);
        }
    }

    /** Relay-sow until the last seed reaches an empty or just-captured house. */
    private void sowRelay(GoosiState.Draft d, GoosiState s, String actor, int myIndex, int from) {
        int seeds = d.pits[from];
        d.pits[from] = 0;
        int cur = from;
        List<Integer> touched = new ArrayList<>();
        List<List<Integer>> laps = new ArrayList<>();
        List<Integer> capturedPits = new ArrayList<>();
        Map<String, Integer> captures = new LinkedHashMap<>();
        Set<String> seen = new HashSet<>();
        boolean cycle = false;
        while (true) {
            // A relay can revisit a board position. Settle that rare loop
            // instead of letting one action hang the room indefinitely.
            String position = cur + ":" + seeds + ":" + Arrays.toString(d.pits);
            if (!seen.add(position)) {
                d.pits[cur] += seeds;
                cycle = true;
                break;
            }
            List<Integer> lap = new ArrayList<>();
            int lapIndex = laps.size();
            boolean lastWasEmpty = false;
            while (seeds > 0) {
                cur = (cur + 1) % 12;
                lastWasEmpty = d.pits[cur] == 0;
                d.pits[cur]++;
                lap.add(cur);
                touched.add(cur);
                seeds--;
                if (d.pits[cur] == 4) {
                    d.pits[cur] = 0;
                    d.scores[myIndex] += 4;
                    capturedPits.add(cur);
                    captures.put(lapIndex + ":" + (lap.size() - 1), cur);
                }
            }
            laps.add(lap);
            if (lastWasEmpty || d.pits[cur] == 0) break;
            seeds = d.pits[cur];
            d.pits[cur] = 0;
        }

        int captured = capturedPits.size() * 4;
        d.emit("SOWN", Map.of(
                "by", actor, "from", from, "touched", touched,
                "laps", laps, "captures", captures,
                "capturedPits", capturedPits, "finalPits", pitsSnapshot(d.pits),
                "scores", scoresSnapshot(d.players, d.scores)));
        if (!capturedPits.isEmpty()) {
            d.emit("CAPTURED", Map.of(
                    "by", actor,
                    "pits", capturedPits,
                    "count", captured,
                    "duringSow", true,
                    "scores", scoresSnapshot(d.players, d.scores)));
        }

        if (cycle) {
            finishFromScores(d, s);
            return;
        }

        if (d.scores[myIndex] > 24) {
            finishFromScores(d, s);
            return;
        }
        advanceTurn(d, s);
    }

    /** Classic Oware Abapa: one sow, then a backward chain of opponent twos or threes. */
    private void sowOware(GoosiState.Draft d, GoosiState s, String actor, int myIndex, int from) {
        require(owareLegalPits(s.pits, s.owner, actor).contains(from),
                "MUST_FEED", "choose a house that feeds your opponent");
        int seeds = d.pits[from];
        d.pits[from] = 0;
        int cur = from;
        List<Integer> touched = new ArrayList<>();
        while (seeds > 0) {
            cur = (cur + 1) % 12;
            if (cur == from) continue;
            d.pits[cur]++;
            touched.add(cur);
            seeds--;
        }

        List<Integer> capturedPits = owareCaptureChain(d.pits, d.owner, actor, cur);
        int captured = capturedPits.stream().mapToInt(pit -> d.pits[pit]).sum();
        int opponentSeeds = 0;
        for (int i = 0; i < 12; i++) {
            if (!actor.equals(d.owner[i])) opponentSeeds += d.pits[i];
        }
        if (captured == opponentSeeds) {
            capturedPits = List.of();
            captured = 0;
        } else {
            for (int pit : capturedPits) d.pits[pit] = 0;
            d.scores[myIndex] += captured;
        }
        d.emit("SOWN", Map.of(
                "by", actor, "from", from, "touched", touched,
                "laps", List.of(touched), "capturedPits", capturedPits));
        if (!capturedPits.isEmpty()) {
            d.emit("CAPTURED", Map.of(
                    "by", actor, "pits", capturedPits, "count", captured,
                    "scores", scoresSnapshot(d.players, d.scores)));
        }
        if (d.scores[myIndex] > 24) {
            finishFromScores(d, s);
            return;
        }
        advanceTurn(d, s);
    }

    private static List<Integer> owareCaptureChain(int[] pits, String[] owner, String actor, int last) {
        if (actor.equals(owner[last]) || (pits[last] != 2 && pits[last] != 3)) return List.of();
        List<Integer> captured = new ArrayList<>();
        int pit = last;
        while (!actor.equals(owner[pit]) && (pits[pit] == 2 || pits[pit] == 3)) {
            captured.add(pit);
            pit = (pit + 11) % 12;
        }
        return captured;
    }

    static List<Integer> legalPits(int[] pits, String[] owner, String actor) {
        List<Integer> nonEmpty = new ArrayList<>();
        for (int i = 0; i < 12; i++) {
            if (actor.equals(owner[i]) && pits[i] > 0) nonEmpty.add(i);
        }
        return nonEmpty;
    }

    private static List<Integer> legalPits(GoosiState s, String actor) {
        return GoosiConfig.OWARE.equals(s.config.mode())
                ? owareLegalPits(s.pits, s.owner, actor)
                : legalPits(s.pits, s.owner, actor);
    }

    private static List<Integer> owareLegalPits(int[] pits, String[] owner, String actor) {
        List<Integer> nonEmpty = legalPits(pits, owner, actor);
        boolean opponentEmpty = true;
        for (int i = 0; i < pits.length; i++) {
            if (!actor.equals(owner[i]) && pits[i] > 0) opponentEmpty = false;
        }
        if (!opponentEmpty) return nonEmpty;
        return nonEmpty.stream().filter(from -> feedsOpponent(pits, owner, actor, from)).toList();
    }

    private static boolean feedsOpponent(int[] pits, String[] owner, String actor, int from) {
        int seeds = pits[from];
        int cur = from;
        while (seeds > 0) {
            cur = (cur + 1) % 12;
            if (cur == from) continue;
            if (!actor.equals(owner[cur])) return true;
            seeds--;
        }
        return false;
    }

    private void advanceTurn(GoosiState.Draft d, GoosiState s) {
        int n = s.players.size();
        int next = (d.turnIndex + 1) % n;
        String nextPlayer = s.players.get(next);
        List<Integer> nextLegal = GoosiConfig.OWARE.equals(s.config.mode())
                ? owareLegalPits(d.pits, d.owner, nextPlayer)
                : legalPits(d.pits, d.owner, nextPlayer);
        if (nextLegal.isEmpty()) {
            if (GoosiConfig.OWARE.equals(s.config.mode())) {
                finishOware(d, s);
            } else {
                finishFromScores(d, s);
            }
            return;
        }
        d.turnIndex = next;
        d.phase = "TurnP" + next;
        d.round++;
        d.emit("TURN_STARTED", Map.of(
                "player", nextPlayer,
                "legalPits", nextLegal));
    }

    private void finishOware(GoosiState.Draft d, GoosiState s) {
        for (int i = 0; i < d.pits.length; i++) {
            if (d.pits[i] > 0) {
                int ownerIndex = s.indexOf(d.owner[i]);
                d.scores[ownerIndex] += d.pits[i];
                d.pits[i] = 0;
            }
        }
        finishFromScores(d, s);
    }

    private void finishFromScores(GoosiState.Draft d, GoosiState s) {
        int n = s.players.size();
        int best = Integer.MIN_VALUE;
        List<String> winners = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            if (d.scores[i] > best) {
                best = d.scores[i];
                winners.clear();
                winners.add(s.players.get(i));
            } else if (d.scores[i] == best) {
                winners.add(s.players.get(i));
            }
        }
        boolean tie = winners.size() > 1;
        Map<String, String> outcome = new LinkedHashMap<>();
        for (int i = 0; i < n; i++) {
            String pid = s.players.get(i);
            outcome.put(pid, winners.contains(pid) ? (tie ? "tied" : "won") : "lost");
        }
        String winningSide = tie ? "tie" : winners.get(0);
        d.win = new WinResult(winningSide, outcome);
        d.phase = "Results";
        d.emit("GAME_OVER", Map.of(
                "winningSide", winningSide, "winners", winners,
                "scores", scoresSnapshot(s.players, d.scores)));
    }

    // ---------------------------------------------------------------- win + views

    @Override
    public Optional<WinResult> checkWinCondition(GameState state) {
        return Optional.ofNullable(((GoosiState) state).win);
    }

    @Override
    public java.util.Set<String> playersToAct(GameState state) {
        GoosiState s = (GoosiState) state;
        if (s.finished()) return java.util.Set.of();
        return java.util.Set.of(s.players.get(s.turnIndex));
    }

    @Override
    public PlayerVisibleState visibleStateFor(GameState state, String playerId) {
        return new PlayerVisibleState(commonView((GoosiState) state));
    }

    @Override
    public PublicBroadcastState broadcastState(GameState state) {
        return new PublicBroadcastState(commonView((GoosiState) state));
    }

    /** Everything's public in Goosi — both views are identical, same as Draughts. */
    private Map<String, Object> commonView(GoosiState s) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("phase", s.phase);
        m.put("round", s.round);
        m.put("players", s.players);
        m.put("turnIndex", s.turnIndex);
        m.put("pitsPerPlayer", s.pitsPerPlayer());
        m.put("pits", pitsSnapshot(s.pits));
        m.put("owner", ownerSnapshot(s.owner));
        m.put("scores", scoresSnapshot(s.players, s.scores));
        m.put("mode", s.config.mode());
        m.put("legalPits", s.finished()
                ? List.of()
                : legalPits(s, s.players.get(s.turnIndex)));
        return m;
    }

    private static List<Integer> pitsSnapshot(int[] pits) {
        List<Integer> out = new ArrayList<>(pits.length);
        for (int p : pits) out.add(p);
        return out;
    }

    private static List<String> ownerSnapshot(String[] owner) {
        return List.of(owner);
    }

    private static Map<String, Integer> scoresSnapshot(List<String> players, int[] scores) {
        Map<String, Integer> out = new LinkedHashMap<>();
        for (int i = 0; i < players.size(); i++) {
            out.put(players.get(i), scores[i]);
        }
        return out;
    }

    @Override
    public List<GameEvent> drainEvents(GameState prev, GameState next) {
        List<GameEvent> a = ((GoosiState) prev).events();
        List<GameEvent> b = ((GoosiState) next).events();
        return b.subList(a.size(), b.size());
    }

    // ---------------------------------------------------------------- helpers

    private static int intField(PlayerAction a, String key) {
        Object v = a.data().get(key);
        if (v instanceof Number n) {
            return n.intValue();
        }
        throw new RuleViolation("BAD_ACTION_DATA", "missing or non-numeric '" + key + "'");
    }

    private static void require(boolean condition, String code, String message) {
        if (!condition) {
            throw new RuleViolation(code, message);
        }
    }
}
