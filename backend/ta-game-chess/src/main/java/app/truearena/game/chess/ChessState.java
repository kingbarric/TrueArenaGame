package app.truearena.game.chess;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.WinResult;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Immutable snapshot of a chess game, built only via {@link Draft} — the same
 * convention as {@code DraughtsState}. Nothing is secret in chess, so every
 * viewer sees the same projection.
 *
 * <p>Like Draughts, the phase name carries whose turn it is ({@code TurnW} /
 * {@code TurnB}) so the orchestrator arms a fresh timer each turn; the
 * duration comes from that side's own clock (see
 * {@link ChessModule#runningClockMs}).
 */
public final class ChessState implements GameState {

    static final String TURN_WHITE = "TurnW";
    static final String TURN_BLACK = "TurnB";
    static final String RESULTS = "Results";

    final String phase;
    final int round;
    final String white;
    final String black;
    final Position position;

    /** Banked clock time. The side to move's runs down from here; the other's is exact. */
    final long whiteClockMs;
    final long blackClockMs;

    /** How many times each position has occurred since the last irreversible move. */
    final Map<String, Integer> positionCounts;
    final List<String> sanMoves;
    final List<String> uciMoves;
    /** Codes of the pieces each side has taken, in capture order. */
    final List<String> capturedByWhite;
    final List<String> capturedByBlack;
    final Integer lastMoveFrom;
    final Integer lastMoveTo;

    final String pendingDrawOffer;
    /** Ply at which each side last offered a draw — one offer per move, so it can't be spammed. */
    final int whiteLastOfferPly;
    final int blackLastOfferPly;

    final WinResult win;
    final String resultReason;

    final ChessConfig config;
    final Set<String> appliedActionIds;
    final List<GameEvent> events;
    final long seq;

    /** The game just before the last move (one step back only), for an agreed undo. */
    final ChessState undoTo;
    /** Who played that last move — the only one who may ask to take it back. */
    final String undoMover;
    /** Asked for an undo, waiting on the other player. */
    final String pendingUndo;

    private ChessState(Draft d) {
        this.phase = d.phase;
        this.round = d.round;
        this.white = d.white;
        this.black = d.black;
        this.position = d.position;
        this.whiteClockMs = d.whiteClockMs;
        this.blackClockMs = d.blackClockMs;
        this.positionCounts = Map.copyOf(d.positionCounts);
        this.sanMoves = List.copyOf(d.sanMoves);
        this.uciMoves = List.copyOf(d.uciMoves);
        this.capturedByWhite = List.copyOf(d.capturedByWhite);
        this.capturedByBlack = List.copyOf(d.capturedByBlack);
        this.lastMoveFrom = d.lastMoveFrom;
        this.lastMoveTo = d.lastMoveTo;
        this.pendingDrawOffer = d.pendingDrawOffer;
        this.whiteLastOfferPly = d.whiteLastOfferPly;
        this.blackLastOfferPly = d.blackLastOfferPly;
        this.win = d.win;
        this.resultReason = d.resultReason;
        this.config = d.config;
        this.appliedActionIds = Set.copyOf(d.appliedActionIds);
        this.events = List.copyOf(d.events);
        this.seq = d.seq;
        this.undoTo = d.undoTo;
        this.undoMover = d.undoMover;
        this.pendingUndo = d.pendingUndo;
    }

    /** This state without its own undo history — what an undo goes back to. */
    ChessState withoutUndo() {
        Draft d = new Draft(this);
        d.undoTo = null;
        d.undoMover = null;
        d.pendingUndo = null;
        return d.build();
    }

    @Override public String phase() { return phase; }
    @Override public int round() { return round; }
    @Override public boolean finished() { return RESULTS.equals(phase); }
    @Override public List<GameEvent> events() { return events; }

    public Position position() {
        return position;
    }

    String playerOf(Color color) {
        return color == Color.WHITE ? white : black;
    }

    Color colorOf(String playerId) {
        if (playerId.equals(white)) return Color.WHITE;
        if (playerId.equals(black)) return Color.BLACK;
        return null;
    }

    long clockMs(Color color) {
        return color == Color.WHITE ? whiteClockMs : blackClockMs;
    }

    int repetitionCount() {
        return positionCounts.getOrDefault(position.repetitionKey(), 0);
    }

    /** Mutable builder — the only way to derive a new {@link ChessState}. */
    static final class Draft {
        String phase;
        int round;
        String white;
        String black;
        Position position;
        long whiteClockMs;
        long blackClockMs;
        Map<String, Integer> positionCounts = new LinkedHashMap<>();
        List<String> sanMoves = new ArrayList<>();
        List<String> uciMoves = new ArrayList<>();
        List<String> capturedByWhite = new ArrayList<>();
        List<String> capturedByBlack = new ArrayList<>();
        Integer lastMoveFrom;
        Integer lastMoveTo;
        String pendingDrawOffer;
        int whiteLastOfferPly = -1;
        int blackLastOfferPly = -1;
        WinResult win;
        String resultReason;
        ChessConfig config;
        Set<String> appliedActionIds = new LinkedHashSet<>();
        List<GameEvent> events = new ArrayList<>();
        long seq;
        ChessState undoTo;
        String undoMover;
        String pendingUndo;

        Draft() {
        }

        Draft(ChessState s) {
            this.phase = s.phase;
            this.round = s.round;
            this.white = s.white;
            this.black = s.black;
            this.position = s.position;
            this.whiteClockMs = s.whiteClockMs;
            this.blackClockMs = s.blackClockMs;
            this.positionCounts = new LinkedHashMap<>(s.positionCounts);
            this.sanMoves = new ArrayList<>(s.sanMoves);
            this.uciMoves = new ArrayList<>(s.uciMoves);
            this.capturedByWhite = new ArrayList<>(s.capturedByWhite);
            this.capturedByBlack = new ArrayList<>(s.capturedByBlack);
            this.lastMoveFrom = s.lastMoveFrom;
            this.lastMoveTo = s.lastMoveTo;
            this.pendingDrawOffer = s.pendingDrawOffer;
            this.whiteLastOfferPly = s.whiteLastOfferPly;
            this.blackLastOfferPly = s.blackLastOfferPly;
            this.win = s.win;
            this.resultReason = s.resultReason;
            this.config = s.config;
            this.appliedActionIds = new LinkedHashSet<>(s.appliedActionIds);
            this.events = new ArrayList<>(s.events);
            this.seq = s.seq;
            this.undoTo = s.undoTo;
            this.undoMover = s.undoMover;
            this.pendingUndo = s.pendingUndo;
        }

        ChessState build() {
            return new ChessState(this);
        }

        void emit(String type, Map<String, Object> payload) {
            events.add(GameEvent.pub(++seq, type, payload));
        }

        String playerOf(Color color) {
            return color == Color.WHITE ? white : black;
        }

        Color colorOf(String playerId) {
            if (playerId.equals(white)) return Color.WHITE;
            if (playerId.equals(black)) return Color.BLACK;
            return null;
        }

        long clockMs(Color color) {
            return color == Color.WHITE ? whiteClockMs : blackClockMs;
        }

        void setClockMs(Color color, long ms) {
            if (color == Color.WHITE) whiteClockMs = ms;
            else blackClockMs = ms;
        }

        int lastOfferPly(Color color) {
            return color == Color.WHITE ? whiteLastOfferPly : blackLastOfferPly;
        }

        void setLastOfferPly(Color color, int ply) {
            if (color == Color.WHITE) whiteLastOfferPly = ply;
            else blackLastOfferPly = ply;
        }

        /** Records the position now on the board for repetition counting. */
        void countPosition() {
            if (position.halfmoveClock() == 0) {
                // A pawn move or capture can never be undone, so nothing
                // before it can recur — keep the map small.
                positionCounts.clear();
            }
            positionCounts.merge(position.repetitionKey(), 1, Integer::sum);
        }
    }
}
