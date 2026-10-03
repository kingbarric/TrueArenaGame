package app.truearena.game.draughts;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.WinResult;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Immutable snapshot of a Draughts game. Built only via {@link Draft}, same
 * convention as {@code TruearenaState}/{@code WordBluffState}. Nothing here
 * is secret — both players always see the whole board — so unlike those two
 * modules there's no player-scoped view to worry about.
 */
public final class DraughtsState implements GameState {

    static final String SIDE_A = "A";
    static final String SIDE_B = "B";

    // Phase doubles as whose turn it is ("TurnA"/"TurnB") rather than a plain
    // "Turn" plus a separate side field — GameOrchestrator only resets a
    // phase's timer when the *phase name* changes (see rescheduleTimer), so
    // encoding the side in the phase name is what makes each player actually
    // get their own fresh per-turn clock instead of sharing one that never
    // resets after the first move.
    final String phase;
    final int round;
    final String playerA;
    final String playerB;
    final Piece[] board; // index 0-49, see Board; null = empty

    /** Non-null only mid capture-chain — the square that must keep capturing. */
    final Integer activeSquare;
    /** How many captures this turn must total before it can end; 0 = no capture forced. */
    final int requiredCaptureCount;
    final int capturedSoFarThisTurn;

    final DraughtsConfig config;
    final Set<String> appliedActionIds;
    final List<GameEvent> events;
    final long seq;
    final WinResult win;
    final String pendingDrawOffer;

    private DraughtsState(Draft d) {
        this.phase = d.phase;
        this.round = d.round;
        this.playerA = d.playerA;
        this.playerB = d.playerB;
        this.board = d.board.clone();
        this.activeSquare = d.activeSquare;
        this.requiredCaptureCount = d.requiredCaptureCount;
        this.capturedSoFarThisTurn = d.capturedSoFarThisTurn;
        this.config = d.config;
        this.appliedActionIds = Set.copyOf(d.appliedActionIds);
        this.events = List.copyOf(d.events);
        this.seq = d.seq;
        this.win = d.win;
        this.pendingDrawOffer = d.pendingDrawOffer;
    }

    @Override public String phase() { return phase; }
    @Override public int round() { return round; }
    @Override public boolean finished() { return "Results".equals(phase); }
    @Override public List<GameEvent> events() { return events; }

    String playerOf(String side) {
        return SIDE_A.equals(side) ? playerA : playerB;
    }

    /**
     * Whose turn it is — derived from the phase name, see the field comment
     * above. The Grace phases are still that side's turn: they can play
     * right up to the moment the last one expires.
     */
    String turnSide() {
        return phase.startsWith("TurnA") || phase.startsWith("GraceA") ? SIDE_A : SIDE_B;
    }

    String sideOf(String playerId) {
        if (playerId.equals(playerA)) return SIDE_A;
        if (playerId.equals(playerB)) return SIDE_B;
        return null;
    }

    String otherSide(String side) {
        return SIDE_A.equals(side) ? SIDE_B : SIDE_A;
    }

    int pieceCount(String side) {
        int n = 0;
        for (Piece p : board) {
            if (p != null && p.side().equals(side)) n++;
        }
        return n;
    }

    /** Mutable builder — the only way to derive a new {@link DraughtsState}. */
    static final class Draft {
        String phase;
        int round;
        String playerA;
        String playerB;
        Piece[] board = new Piece[Board.SIZE];
        Integer activeSquare;
        int requiredCaptureCount;
        int capturedSoFarThisTurn;
        DraughtsConfig config;
        Set<String> appliedActionIds = new LinkedHashSet<>();
        List<GameEvent> events = new ArrayList<>();
        long seq;
        WinResult win;
        String pendingDrawOffer;

        Draft() {
        }

        Draft(DraughtsState s) {
            this.phase = s.phase;
            this.round = s.round;
            this.playerA = s.playerA;
            this.playerB = s.playerB;
            this.board = s.board.clone();
            this.activeSquare = s.activeSquare;
            this.requiredCaptureCount = s.requiredCaptureCount;
            this.capturedSoFarThisTurn = s.capturedSoFarThisTurn;
            this.config = s.config;
            this.appliedActionIds = new LinkedHashSet<>(s.appliedActionIds);
            this.events = new ArrayList<>(s.events);
            this.seq = s.seq;
            this.win = s.win;
            this.pendingDrawOffer = s.pendingDrawOffer;
        }

        DraughtsState build() {
            return new DraughtsState(this);
        }

        void emit(String type, Map<String, Object> payload) {
            events.add(GameEvent.pub(++seq, type, payload));
        }
    }
}
