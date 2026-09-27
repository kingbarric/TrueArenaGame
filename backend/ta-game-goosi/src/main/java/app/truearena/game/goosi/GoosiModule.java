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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Goosi — the fourth game type. A 16-pit sowing/capture board in the Mancala
 * family, 2 or 4 players sharing one fixed ring of 16 pits (no separate
 * "store" pits — captured seeds go straight to each player's score):
 *
 * <ul>
 *   <li><b>2 players</b>: pits 0-7 belong to player 0, pits 8-15 to player 1
 *       — the classic two-opposing-rows layout.</li>
 *   <li><b>4 players</b>: pits are split into four arcs of 4 — player k owns
 *       {@code [4k, 4k+3]} — read as four sides of a ring/table, each player
 *       across from the player two seats over.</li>
 * </ul>
 *
 * <p>Sowing always moves in increasing pit index (mod 16), one seed per pit,
 * regardless of player count — for 4 players this naturally sows through
 * every other player's pits on the way around, not just the two rows a 2p
 * game would have. "Opposite pit" for a capture is always {@code (pit+8)%16}
 * — the pit directly across the ring — which is the same formula for both
 * layouts (see {@link GoosiState#opposite}).
 *
 * <p><b>Capture</b>: if your last sown seed lands in a pit that was empty
 * and it's one of your own pits, you capture that seed plus everything in
 * the opposite pit, straight to your score. Landing in an empty pit that
 * isn't yours (or a pit that already had seeds) never captures.
 *
 * <p><b>No extra turns</b> — every sow simply passes to the next player, even
 * on a capture. Deliberately simpler than Kalah's "land in your store, go
 * again" rule, since there's no store here.
 *
 * <p><b>End game</b>: if the player about to move has no seeds anywhere in
 * their own pits, the game ends immediately — every remaining pit's seeds
 * sweep into whichever player owns that pit's own score. Highest score wins;
 * ties are possible and reported as such.
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
        for (int i = 0; i < 4; i++) {
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
        if (n != 2 && n != 4) {
            throw new RuleViolation("NEEDS_TWO_OR_FOUR_PLAYERS", "Goosi is 2 or 4 players — got " + n);
        }
        List<String> shuffled = new ArrayList<>(playerIds);
        rng.shuffle(shuffled);

        GoosiState.Draft d = new GoosiState.Draft();
        d.config = config;
        d.players = shuffled;
        d.scores = new int[n];
        int pitsPerPlayer = 16 / n;
        for (int p = 0; p < n; p++) {
            for (int i = 0; i < pitsPerPlayer; i++) {
                d.owner[p * pitsPerPlayer + i] = shuffled.get(p);
            }
        }
        for (int i = 0; i < 16; i++) {
            d.pits[i] = config.seedsPerPit();
        }
        d.turnIndex = 0;
        d.phase = "TurnP0";
        d.round = 1;

        d.emit("GAME_STARTED", Map.of(
                "players", List.copyOf(shuffled),
                "pits", pitsSnapshot(d.pits),
                "owner", ownerSnapshot(d.owner),
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
            default -> throw new RuleViolation("UNKNOWN_ACTION", "no handler for " + action.type());
        }
        return d.build();
    }

    /**
     * A clock running out no longer sows for you. It walks the same ladder
     * Draughts uses: the turn expiring pauses the room, resuming buys
     * {@value #GRACE_SECONDS} more seconds, that expiring pauses again, and
     * only the last {@value #FINAL_GRACE_SECONDS}-second chance running out
     * settles it. Each grace phase waits paused so the time isn't spent
     * while the player is still away.
     *
     * <p>What "settles it" means depends on the table. Head to head, the
     * player who ran out forfeits and the other takes it, exactly as in
     * Draughts. With three or four playing, ending everybody's game because
     * one person walked away would punish the wrong people — that seat just
     * loses its turn and play moves on.
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

    /** Safety valve on relay sowing — see {@link #sow}. Far above any real turn. */
    private static final int MAX_LAPS = 200;

    /** A pit brought to exactly this many seeds is captured by whoever sowed it. */
    private static final int CAPTURE_AT = 4;

    /** Seconds offered after a turn's clock runs out, once somebody resumes. */
    static final int GRACE_SECONDS = 20;

    /** Seconds on the final chance. */
    static final int FINAL_GRACE_SECONDS = 5;

    private void sowAction(GoosiState.Draft d, GoosiState s, PlayerAction a) {
        int myIndex = s.indexOf(a.actor());
        require(myIndex >= 0, "NOT_A_PLAYER", "you're not one of the players in this game");
        require(myIndex == s.turnIndex, "NOT_YOUR_TURN", "it's not your turn");

        int from = intField(a, "pit");
        require(from >= 0 && from < 16, "BAD_PIT", "pit out of range");
        require(a.actor().equals(s.owner[from]), "NOT_YOUR_PIT", "that pit isn't yours");
        require(s.pits[from] > 0, "EMPTY_PIT", "that pit has no seeds to sow");

        sow(d, s, a.actor(), myIndex, from);
    }

    /**
     * Relay sowing with capture-at-four, the way the game is played.
     *
     * <p>You drop the handful one seed per pit. Any pit your seed brings to
     * exactly four is yours — it's emptied into your score the moment it
     * happens, on either side of the board, and a long relay can take
     * several. If the last seed of a pass lands on a pit that still has
     * seeds in it, you scoop that pit up and keep going; the sowing ends
     * when a seed lands somewhere that was empty (or that you just
     * captured, which leaves nothing to pick up).
     *
     * <p>Each pass is recorded in {@code laps}, and every capture notes the
     * lap and position it happened at, so the client can empty the pit at
     * the exact moment the fourth seed lands rather than afterwards — see
     * the sow animation in `goosi_game_screen.dart`.
     */
    private void sow(GoosiState.Draft d, GoosiState s, String actor, int myIndex, int from) {
        int seeds = d.pits[from];
        d.pits[from] = 0;
        int cur = from;
        List<List<Integer>> laps = new ArrayList<>();
        List<Integer> touched = new ArrayList<>();
        List<Map<String, Object>> captures = new ArrayList<>();

        // A relay can in principle cycle; a cap guarantees a turn always
        // ends rather than hanging the room's single writer thread.
        for (int lapNo = 0; lapNo < MAX_LAPS; lapNo++) {
            List<Integer> lap = new ArrayList<>(seeds);
            for (int i = 0; i < seeds; i++) {
                cur = (cur + 1) % 16;
                d.pits[cur]++;
                lap.add(cur);
                touched.add(cur);

                if (d.pits[cur] == CAPTURE_AT) {
                    int taken = d.pits[cur];
                    d.pits[cur] = 0;
                    d.scores[myIndex] += taken;
                    captures.add(Map.of(
                            "lap", lapNo, "index", i, "pit", cur, "count", taken,
                            "scores", scoresSnapshot(d.players, d.scores)));
                }
            }
            laps.add(lap);

            // Nothing left to pick up — either the pit was empty before this
            // seed, or it just reached four and went to the score.
            if (d.pits[cur] <= 1) {
                break;
            }
            seeds = d.pits[cur];
            d.pits[cur] = 0;
        }

        d.emit("SOWN", Map.of(
                "by", actor, "from", from, "touched", touched, "laps", laps, "captures", captures));

        // Emitted after the sowing so a client animating it can show each
        // capture at the point it happened, not before the seeds have moved.
        for (Map<String, Object> capture : captures) {
            d.emit("CAPTURED", Map.of(
                    "by", actor,
                    "pit", capture.get("pit"),
                    "count", capture.get("count"),
                    "scores", capture.get("scores")));
        }

        advanceTurn(d, s);
    }

    private void advanceTurn(GoosiState.Draft d, GoosiState s) {
        int n = s.players.size();
        int next = (d.turnIndex + 1) % n;
        String nextPlayer = s.players.get(next);
        if (!hasAnySeeds(d.pits, d.owner, nextPlayer)) {
            finish(d, s);
            return;
        }
        d.turnIndex = next;
        d.phase = "TurnP" + next;
        d.round++;
        d.emit("TURN_STARTED", Map.of("player", nextPlayer));
    }

    private void finish(GoosiState.Draft d, GoosiState s) {
        // Sweep every remaining seed into whichever player owns that pit.
        for (int i = 0; i < 16; i++) {
            if (d.pits[i] > 0) {
                int idx = s.indexOf(d.owner[i]);
                d.scores[idx] += d.pits[i];
                d.pits[i] = 0;
            }
        }
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

    private static int firstNonEmptyOwnPit(GoosiState s, String player) {
        for (int i = 0; i < 16; i++) {
            if (player.equals(s.owner[i]) && s.pits[i] > 0) return i;
        }
        return -1;
    }

    private static boolean hasAnySeeds(int[] pits, String[] owner, String player) {
        for (int i = 0; i < 16; i++) {
            if (player.equals(owner[i]) && pits[i] > 0) return true;
        }
        return false;
    }

    // ---------------------------------------------------------------- win + views

    @Override
    public Optional<WinResult> checkWinCondition(GameState state) {
        return Optional.ofNullable(((GoosiState) state).win);
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
