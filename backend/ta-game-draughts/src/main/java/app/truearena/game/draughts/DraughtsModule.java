package app.truearena.game.draughts;

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
 * International (10x10, 20-piece) Draughts — a real-time 1v1 game, wired
 * into the same {@code GameOrchestrator}/WS transport as TrueArena and Word
 * Bluff. Two things set this variant apart from plain checkers, both
 * enforced by {@link CaptureEngine}: flying kings, and mandatory capture of
 * the maximum number of pieces available each turn (not just "a" capture).
 * See docs/DEV_REFERENCE.md.
 */
public final class DraughtsModule implements GameModule {

    public static final String GAME_TYPE = "draughts";

    @Override
    public String gameType() {
        return GAME_TYPE;
    }

    @Override
    public List<Phase> definePhases(GameSettings settings) {
        DraughtsConfig config = (DraughtsConfig) settings;
        return List.of(
                new Phase("TurnA", config.turnSeconds()),
                new Phase("TurnB", config.turnSeconds()),
                // Running out of time doesn't lose the game outright — see
                // onPhaseElapsed. Each grace phase waits, paused, until a
                // player resumes, then runs its own shorter clock.
                Phase.awaitingResume("GraceA1", GRACE_SECONDS),
                Phase.awaitingResume("GraceB1", GRACE_SECONDS),
                Phase.awaitingResume("GraceA2", FINAL_GRACE_SECONDS),
                Phase.awaitingResume("GraceB2", FINAL_GRACE_SECONDS),
                Phase.untimed("Results")
        );
    }

    // ---------------------------------------------------------------- setup

    @Override
    public GameState initialState(List<String> playerIds, GameSettings settings, RandomSource rng) {
        DraughtsConfig config = (DraughtsConfig) settings;
        if (playerIds.size() != 2) {
            throw new RuleViolation("NEEDS_TWO_PLAYERS", "Draughts is 1v1 — needs exactly 2 players");
        }
        List<String> shuffled = new ArrayList<>(playerIds);
        rng.shuffle(shuffled);

        DraughtsState.Draft d = new DraughtsState.Draft();
        d.config = config;
        d.playerA = shuffled.get(0);
        d.playerB = shuffled.get(1);
        for (int sq = 0; sq < 20; sq++) {
            d.board[sq] = Piece.A_MAN; // rows 0-3
        }
        for (int sq = 30; sq < 50; sq++) {
            d.board[sq] = Piece.B_MAN; // rows 6-9
        }
        d.phase = "TurnA";
        d.round = 1;
        d.requiredCaptureCount = CaptureEngine.requiredCaptureCount(d.board, DraughtsState.SIDE_A);

        d.emit("GAME_STARTED", Map.of(
                "playerA", d.playerA,
                "playerB", d.playerB,
                "board", boardSnapshot(d.board),
                "turnSeconds", config.turnSeconds()));
        return d.build();
    }

    // ---------------------------------------------------------------- actions

    @Override
    public GameState onPlayerAction(GameState state, PlayerAction action) {
        DraughtsState s = (DraughtsState) state;
        if (s.finished() || s.appliedActionIds.contains(action.actionId())) {
            return s;
        }
        DraughtsState.Draft d = new DraughtsState.Draft(s);
        d.appliedActionIds.add(action.actionId());

        switch (action.type()) {
            case "MOVE" -> move(d, s, action);
            case "FORFEIT" -> forfeit(d, s, action);
            case "OFFER_DRAW" -> offerDraw(d, s, action);
            case "ACCEPT_DRAW" -> acceptDraw(d, s, action);
            default -> throw new RuleViolation("UNKNOWN_ACTION", "no handler for " + action.type());
        }
        return d.build();
    }

    /**
     * Running out of time doesn't lose the game on the spot — someone who
     * put their phone down mid-game shouldn't come back to a loss they never
     * played. Instead the clock expiring walks down a ladder of chances,
     * each one paused until a player resumes so the grace isn't spent while
     * they're still away:
     *
     * <ol>
     *   <li><b>Turn expires</b> → the room pauses. Resuming gives another
     *       {@value #GRACE_SECONDS} seconds.</li>
     *   <li><b>That expires</b> → the room pauses again. Resuming this time
     *       is the last chance, and the client warns before it does.</li>
     *   <li><b>The last chance expires</b> → the turn is forfeit and the
     *       opponent wins.</li>
     * </ol>
     *
     * The ladder is per turn: playing a move returns to a normal full-length
     * turn (see endTurn), so it forgives a lapse rather than counting them
     * up over a game.
     */
    @Override
    public GameState onPhaseElapsed(GameState state, String endedPhase) {
        DraughtsState s = (DraughtsState) state;
        if (s.finished()) {
            return s;
        }
        DraughtsState.Draft d = new DraughtsState.Draft(s);
        String sideOnClock = endedPhase.contains("A") ? DraughtsState.SIDE_A : DraughtsState.SIDE_B;
        String nextPhase = switch (endedPhase) {
            case "TurnA" -> "GraceA1";
            case "TurnB" -> "GraceB1";
            case "GraceA1" -> "GraceA2";
            case "GraceB1" -> "GraceB2";
            default -> null; // the final grace ran out — no chances left
        };
        if (nextPhase == null) {
            finish(d, opposite(sideOnClock));
            return d.build();
        }
        d.phase = nextPhase;
        boolean lastChance = nextPhase.endsWith("2");
        d.emit("TURN_GRACE", Map.of(
                "side", sideOnClock,
                "seconds", lastChance ? FINAL_GRACE_SECONDS : GRACE_SECONDS,
                "lastChance", lastChance));
        return d.build();
    }

    /** Seconds offered after a turn's clock runs out, once the player resumes. */
    static final int GRACE_SECONDS = 20;

    /** Seconds on the final chance — after this the turn is forfeit. */
    static final int FINAL_GRACE_SECONDS = 5;

    private void move(DraughtsState.Draft d, DraughtsState s, PlayerAction a) {
        d.pendingDrawOffer = null;
        String side = s.sideOf(a.actor());
        require(side != null, "NOT_A_PLAYER", "you're not one of the two players in this game");
        require(side.equals(s.turnSide()), "NOT_YOUR_TURN", "it's not your turn");

        int from = intField(a, "from");
        int to = intField(a, "to");
        require(from >= 0 && from < Board.SIZE && to >= 0 && to < Board.SIZE, "BAD_SQUARE", "square out of range");

        if (d.activeSquare != null) {
            require(from == d.activeSquare, "MUST_CONTINUE_CAPTURE", "you must keep capturing with the same piece");
        }
        Piece piece = d.board[from];
        require(piece != null && piece.side().equals(side), "NOT_YOUR_PIECE", "that's not your piece");

        int requiredTotal = d.requiredCaptureCount;
        if (requiredTotal > 0) {
            captureMove(d, side, from, to, requiredTotal);
        } else if (isCaptureLanding(d.board, from, to)) {
            // Captures aren't forced in this room, so this one was a choice
            // — but having chosen it, the sequence still has to be finished.
            optionalCaptureMove(d, side, from, to);
        } else {
            simpleMove(d, side, from, to);
        }
    }

    /** Either player can end the match early — the other side is awarded the win. */
    private void forfeit(DraughtsState.Draft d, DraughtsState s, PlayerAction a) {
        String side = s.sideOf(a.actor());
        require(side != null, "NOT_A_PLAYER", "you're not one of the two players in this game");
        finish(d, opposite(side));
    }

    private void offerDraw(DraughtsState.Draft d, DraughtsState s, PlayerAction a) {
        require(s.sideOf(a.actor()) != null, "NOT_A_PLAYER", "only a player can offer a draw");
        require(s.pendingDrawOffer == null, "DRAW_ALREADY_OFFERED", "a draw offer is already pending");
        d.pendingDrawOffer = a.actor();
        d.emit("DRAW_OFFERED", Map.of("by", a.actor()));
    }

    private void acceptDraw(DraughtsState.Draft d, DraughtsState s, PlayerAction a) {
        require(s.sideOf(a.actor()) != null && s.pendingDrawOffer != null
                && !s.pendingDrawOffer.equals(a.actor()), "NO_DRAW_OFFER", "the other player has not offered a draw");
        d.win = new WinResult("draw", Map.of(d.playerA, "tied", d.playerB, "tied"));
        d.phase = "Results";
        d.pendingDrawOffer = null;
        d.emit("GAME_OVER", Map.of("winningSide", "draw"));
    }

    private void captureMove(DraughtsState.Draft d, String side, int from, int to, int requiredTotal) {
        CaptureEngine.Landing chosen = CaptureEngine.captureLandings(d.board, from).stream()
                .filter(l -> l.to() == to)
                .findFirst()
                .orElseThrow(() -> new RuleViolation("MUST_CAPTURE", "a capture is available and mandatory"));

        Piece[] afterBoard = CaptureEngine.applyCapture(d.board, from, chosen);
        int remainingNeeded = requiredTotal - d.capturedSoFarThisTurn;
        int additionalAvailable = CaptureEngine.maxCaptureCount(afterBoard, to);
        require(1 + additionalAvailable == remainingNeeded, "MUST_TAKE_MAXIMUM",
                "you must play the capture sequence that takes the most pieces");

        d.board = afterBoard;
        d.capturedSoFarThisTurn++;
        d.emit("PIECE_CAPTURED", Map.of("from", from, "to", to, "captured", chosen.captured(), "side", side));

        if (d.capturedSoFarThisTurn < requiredTotal) {
            d.activeSquare = to; // must continue the chain from here
        } else {
            endTurn(d, side, to);
        }
    }

    private static boolean isCaptureLanding(Piece[] board, int from, int to) {
        return CaptureEngine.captureLandings(board, from).stream().anyMatch(l -> l.to() == to);
    }

    /**
     * A capture in a room where captures are optional: no maximum to meet,
     * so any jump goes. The piece must keep taking while it can, which is
     * what stops a chain being abandoned half way for advantage.
     */
    private void optionalCaptureMove(DraughtsState.Draft d, String side, int from, int to) {
        CaptureEngine.Landing chosen = CaptureEngine.captureLandings(d.board, from).stream()
                .filter(l -> l.to() == to)
                .findFirst()
                .orElseThrow(() -> new RuleViolation("ILLEGAL_MOVE", "not a legal capture"));

        d.board = CaptureEngine.applyCapture(d.board, from, chosen);
        d.emit("PIECE_CAPTURED", Map.of("from", from, "to", to, "captured", chosen.captured(), "side", side));

        if (CaptureEngine.maxCaptureCount(d.board, to) > 0) {
            d.activeSquare = to; // still taking — same piece, keep going
        } else {
            endTurn(d, side, to);
        }
    }

    private void simpleMove(DraughtsState.Draft d, String side, int from, int to) {
        require(CaptureEngine.simpleLandings(d.board, from).contains(to), "ILLEGAL_MOVE", "not a legal move");
        d.board = CaptureEngine.applySimpleMove(d.board, from, to);
        d.emit("PIECE_MOVED", Map.of("from", from, "to", to, "side", side));
        endTurn(d, side, to);
    }

    /** Promotes if the landing square earns it, then hands the turn to the other side (or ends the game). */
    private void endTurn(DraughtsState.Draft d, String side, int landedSquare) {
        Piece landed = d.board[landedSquare];
        if (landed != null && !landed.isKing()) {
            int row = Board.rowOf(landedSquare);
            boolean promotes = DraughtsState.SIDE_A.equals(side) ? row == 9 : row == 0;
            if (promotes) {
                d.board[landedSquare] = landed.promoted();
                d.emit("PIECE_PROMOTED", Map.of("square", landedSquare, "side", side));
            }
        }
        d.activeSquare = null;
        d.capturedSoFarThisTurn = 0;

        String next = opposite(side);
        if (!CaptureEngine.hasAnyLegalMove(d.board, next)) {
            finish(d, side);
            return;
        }
        // With captures optional nothing is forced, so the turn starts with
        // no debt to pay — see DraughtsConfig.
        d.requiredCaptureCount = d.config.mandatoryCapture()
                ? CaptureEngine.requiredCaptureCount(d.board, next)
                : 0;
        d.phase = DraughtsState.SIDE_A.equals(next) ? "TurnA" : "TurnB";
        d.round++;
        d.emit("TURN_STARTED", Map.of("side", next, "mustCapture", d.requiredCaptureCount > 0));
    }

    private void finish(DraughtsState.Draft d, String winningSide) {
        Map<String, String> outcome = new LinkedHashMap<>();
        outcome.put(d.playerA, DraughtsState.SIDE_A.equals(winningSide) ? "won" : "lost");
        outcome.put(d.playerB, DraughtsState.SIDE_B.equals(winningSide) ? "won" : "lost");
        d.win = new WinResult(winningSide, outcome);
        d.phase = "Results";
        d.activeSquare = null;
        d.requiredCaptureCount = 0;
        // What the board looked like at the end, so the result screen can
        // say how comfortable the win was rather than just who took it.
        d.emit("GAME_OVER", Map.of(
                "winningSide", winningSide,
                "piecesA", countPieces(d.board, DraughtsState.SIDE_A),
                "piecesB", countPieces(d.board, DraughtsState.SIDE_B)));
    }

    private static int countPieces(Piece[] board, String side) {
        int n = 0;
        for (Piece p : board) {
            if (p != null && p.side().equals(side)) {
                n++;
            }
        }
        return n;
    }

    private static String opposite(String side) {
        return DraughtsState.SIDE_A.equals(side) ? DraughtsState.SIDE_B : DraughtsState.SIDE_A;
    }

    // ---------------------------------------------------------------- win + views

    @Override
    public Optional<WinResult> checkWinCondition(GameState state) {
        return Optional.ofNullable(((DraughtsState) state).win);
    }

    @Override
    public PlayerVisibleState visibleStateFor(GameState state, String playerId) {
        return new PlayerVisibleState(commonView((DraughtsState) state));
    }

    @Override
    public PublicBroadcastState broadcastState(GameState state) {
        return new PublicBroadcastState(commonView((DraughtsState) state));
    }

    /** Everything's public in Draughts — both views are identical, unlike TrueArena/Word Bluff. */
    private Map<String, Object> commonView(DraughtsState s) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("phase", s.phase);
        m.put("round", s.round);
        m.put("playerA", s.playerA);
        m.put("playerB", s.playerB);
        m.put("turnSide", s.turnSide());
        m.put("board", boardSnapshot(s.board));
        m.put("activeSquare", s.activeSquare);
        m.put("mustCapture", s.requiredCaptureCount > 0);
        m.put("mandatoryCapture", s.config.mandatoryCapture());
        m.put("pendingDrawOffer", s.pendingDrawOffer);
        // Server-computed legal destinations per square, keyed by square as a
        // string (JSON object keys must be strings) — so the client never has
        // to reimplement flying-king or mandatory-maximum-capture logic just
        // to highlight where a tap is allowed to land.
        m.put("legalMoves", legalMovesBySquare(s));
        return m;
    }

    private Map<String, List<Integer>> legalMovesBySquare(DraughtsState s) {
        Map<String, List<Integer>> out = new LinkedHashMap<>();
        String side = s.turnSide();
        if (s.activeSquare != null && s.requiredCaptureCount == 0) {
            // Mid-chain in an optional-capture room: any continuing jump goes.
            out.put(String.valueOf(s.activeSquare),
                    CaptureEngine.captureLandings(s.board, s.activeSquare).stream()
                            .map(CaptureEngine.Landing::to)
                            .toList());
            return out;
        }
        if (s.activeSquare != null) {
            List<Integer> landings = CaptureEngine.captureLandings(s.board, s.activeSquare).stream()
                    .filter(l -> 1 + CaptureEngine.maxCaptureCount(CaptureEngine.applyCapture(s.board, s.activeSquare, l), l.to())
                            == s.requiredCaptureCount - s.capturedSoFarThisTurn)
                    .map(CaptureEngine.Landing::to)
                    .toList();
            out.put(String.valueOf(s.activeSquare), landings);
            return out;
        }
        for (int sq = 0; sq < Board.SIZE; sq++) {
            Piece p = s.board[sq];
            if (p == null || !p.side().equals(side)) {
                continue;
            }
            int from = sq;
            List<Integer> dest;
            if (s.requiredCaptureCount > 0) {
                dest = CaptureEngine.captureLandings(s.board, from).stream()
                        .filter(l -> 1 + CaptureEngine.maxCaptureCount(CaptureEngine.applyCapture(s.board, from, l), l.to())
                                == s.requiredCaptureCount)
                        .map(CaptureEngine.Landing::to)
                        .toList();
            } else {
                // Nothing forced: ordinary moves, plus any capture on offer
                // when this room doesn't make them compulsory.
                List<Integer> open = new ArrayList<>(CaptureEngine.simpleLandings(s.board, from));
                if (!s.config.mandatoryCapture()) {
                    CaptureEngine.captureLandings(s.board, from).forEach(l -> open.add(l.to()));
                }
                dest = open;
            }
            if (!dest.isEmpty()) {
                out.put(String.valueOf(sq), dest);
            }
        }
        return out;
    }

    private static List<String> boardSnapshot(Piece[] board) {
        List<String> out = new ArrayList<>(board.length);
        for (Piece p : board) {
            out.add(p == null ? null : p.name());
        }
        return out;
    }

    @Override
    public List<GameEvent> drainEvents(GameState prev, GameState next) {
        List<GameEvent> a = ((DraughtsState) prev).events();
        List<GameEvent> b = ((DraughtsState) next).events();
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
