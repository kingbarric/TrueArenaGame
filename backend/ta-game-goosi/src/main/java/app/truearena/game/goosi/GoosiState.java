package app.truearena.game.goosi;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.WinResult;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Immutable snapshot of a Goosi game. Built only via {@link Draft}, same
 * convention as {@code DraughtsState}/{@code WordBluffState}. Nothing here is
 * secret — every pit is visible to everyone — so like Draughts there's no
 * player-scoped view to worry about.
 *
 * <p>The board is always exactly 16 pits (index 0-15) arranged in one ring,
 * regardless of player count — see {@link GoosiModule}'s class doc for how
 * 2 vs. 4 players divide it up and what "opposite pit" means. {@link #owner}
 * is fixed for the whole game (pit index -> owning player id); {@code pits}
 * is the live seed count per index.
 *
 * <p>{@code phase} doubles as whose turn it is ("TurnP0".."TurnP3") rather
 * than a plain "Turn" plus a separate index field — same reason as Draughts'
 * "TurnA"/"TurnB": {@code GameOrchestrator.rescheduleTimer} only resets a
 * phase's timer when the phase *name* changes.
 */
public final class GoosiState implements GameState {

    final String phase;
    final int round;
    final List<String> players;
    final String[] owner; // length 16, fixed at game start
    final int[] pits; // length 16, live seed counts
    final int[] scores; // parallel to players
    final int turnIndex;

    final GoosiConfig config;
    final Set<String> appliedActionIds;
    final List<GameEvent> events;
    final long seq;
    final WinResult win;

    private GoosiState(Draft d) {
        this.phase = d.phase;
        this.round = d.round;
        this.players = List.copyOf(d.players);
        this.owner = d.owner.clone();
        this.pits = d.pits.clone();
        this.scores = d.scores.clone();
        this.turnIndex = d.turnIndex;
        this.config = d.config;
        this.appliedActionIds = Set.copyOf(d.appliedActionIds);
        this.events = List.copyOf(d.events);
        this.seq = d.seq;
        this.win = d.win;
    }

    @Override public String phase() { return phase; }
    @Override public int round() { return round; }
    @Override public boolean finished() { return "Results".equals(phase); }
    @Override public List<GameEvent> events() { return events; }

    int indexOf(String playerId) {
        return players.indexOf(playerId);
    }

    int pitsPerPlayer() {
        return 16 / players.size();
    }

    /** The pit directly across the 16-pit ring — same formula for both 2p and 4p layouts. */
    static int opposite(int pit) {
        return (pit + 8) % 16;
    }

    boolean hasAnySeeds(String playerId) {
        for (int i = 0; i < 16; i++) {
            if (playerId.equals(owner[i]) && pits[i] > 0) return true;
        }
        return false;
    }

    /** Mutable builder — the only way to derive a new {@link GoosiState}. */
    static final class Draft {
        String phase;
        int round;
        List<String> players = new ArrayList<>();
        String[] owner = new String[16];
        int[] pits = new int[16];
        int[] scores;
        int turnIndex;
        GoosiConfig config;
        Set<String> appliedActionIds = new LinkedHashSet<>();
        List<GameEvent> events = new ArrayList<>();
        long seq;
        WinResult win;

        Draft() {
        }

        Draft(GoosiState s) {
            this.phase = s.phase;
            this.round = s.round;
            this.players = new ArrayList<>(s.players);
            this.owner = s.owner.clone();
            this.pits = s.pits.clone();
            this.scores = s.scores.clone();
            this.turnIndex = s.turnIndex;
            this.config = s.config;
            this.appliedActionIds = new LinkedHashSet<>(s.appliedActionIds);
            this.events = new ArrayList<>(s.events);
            this.seq = s.seq;
            this.win = s.win;
        }

        GoosiState build() {
            return new GoosiState(this);
        }

        void emit(String type, java.util.Map<String, Object> payload) {
            events.add(GameEvent.pub(++seq, type, payload));
        }
    }
}
