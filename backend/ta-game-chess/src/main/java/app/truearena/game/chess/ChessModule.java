package app.truearena.game.chess;

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
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.OptionalLong;
import java.util.Set;

/**
 * Chess under the FIDE Laws, wired into the same {@code GameOrchestrator}/WS
 * transport as the other games. {@link Position} owns the board rules; this
 * class owns the game around them — turns, clocks, and how a game ends:
 *
 * <ul>
 *   <li><b>Decisive:</b> checkmate, resignation, or a flag falling while the
 *       opponent could still mate (otherwise a timeout is drawn, FIDE 6.9).</li>
 *   <li><b>Automatic draws:</b> stalemate, a dead position, the 75-move rule
 *       and fivefold repetition — checkmate always takes precedence.</li>
 *   <li><b>Claimed draws:</b> threefold repetition and the 50-move rule, by
 *       the player to move, either on the position in front of them or on
 *       the move they're about to play (FIDE 9.2, 9.3).</li>
 *   <li><b>Agreed draws:</b> an offer stands until accepted, declined, or the
 *       opponent moves instead.</li>
 * </ul>
 *
 * <p>Clocks are server-authoritative: the orchestrator measures time and
 * stamps every action with the running clock's remaining milliseconds
 * ({@link GameModule#CLOCK_REMAINING_KEY}); this module banks it, adds the
 * increment, and ends the game when it reaches zero.
 */
public final class ChessModule implements GameModule {

    public static final String GAME_TYPE = "chess";

    static final String REASON_CHECKMATE = "checkmate";
    static final String REASON_RESIGNATION = "resignation";
    static final String REASON_FORFEIT = "forfeit";
    static final String REASON_TIMEOUT = "timeout";
    static final String REASON_TIMEOUT_NO_MATERIAL = "timeout_vs_insufficient_material";
    static final String REASON_STALEMATE = "stalemate";
    static final String REASON_DEAD_POSITION = "dead_position";
    static final String REASON_SEVENTY_FIVE_MOVES = "seventy_five_move_rule";
    static final String REASON_FIVEFOLD = "fivefold_repetition";
    static final String REASON_THREEFOLD = "threefold_repetition";
    static final String REASON_FIFTY_MOVES = "fifty_move_rule";
    static final String REASON_AGREEMENT = "agreement";

    /** Halfmoves without a capture or pawn move after which a draw may be claimed (50 moves each). */
    static final int FIFTY_MOVE_HALFMOVES = 100;
    /** …and after which it is drawn automatically (75 moves each). */
    static final int SEVENTY_FIVE_MOVE_HALFMOVES = 150;

    @Override
    public String gameType() {
        return GAME_TYPE;
    }

    @Override
    public List<Phase> definePhases(GameSettings settings) {
        ChessConfig config = (ChessConfig) settings;
        // The nominal duration is the starting clock; the real deadline each
        // turn is whatever that side has left — see runningClockMs.
        return List.of(
                new Phase(ChessState.TURN_WHITE, config.initialSeconds()),
                new Phase(ChessState.TURN_BLACK, config.initialSeconds()),
                Phase.untimed(ChessState.RESULTS));
    }

    // ---------------------------------------------------------------- setup

    @Override
    public GameState initialState(List<String> playerIds, GameSettings settings, RandomSource rng) {
        if (playerIds.size() != 2) {
            throw new RuleViolation("NEEDS_TWO_PLAYERS", "Chess is 1v1 — needs exactly 2 players");
        }
        List<String> shuffled = new ArrayList<>(playerIds);
        rng.shuffle(shuffled);
        return start(shuffled.get(0), shuffled.get(1), (ChessConfig) settings, Position.initial());
    }

    /** A game from an arbitrary position — the engine's entry point for tests and analysis. */
    static ChessState start(String white, String black, ChessConfig config, Position position) {
        ChessState.Draft d = new ChessState.Draft();
        d.config = config;
        d.white = white;
        d.black = black;
        d.position = position;
        d.whiteClockMs = config.initialMs();
        d.blackClockMs = config.initialMs();
        d.phase = turnPhase(position.sideToMove());
        d.round = 1;
        d.countPosition();
        d.emit("GAME_STARTED", Map.of(
                "white", white,
                "black", black,
                "fen", position.fen(),
                "initialMs", config.initialMs(),
                "incrementMs", config.incrementMs()));
        return d.build();
    }

    // ---------------------------------------------------------------- actions

    @Override
    public GameState onPlayerAction(GameState state, PlayerAction action) {
        ChessState s = (ChessState) state;
        if (s.finished() || s.appliedActionIds.contains(action.actionId())) {
            return s;
        }
        ChessState.Draft d = new ChessState.Draft(s);
        d.appliedActionIds.add(action.actionId());

        // The stamp is always the *running* clock, whoever acted. If it's
        // already empty, the flag fell before this action arrived — that's
        // the first thing that happened, so it's what ends the game.
        Long remaining = clockRemaining(action);
        if (remaining != null && remaining <= 0) {
            flagFall(d, d.position.sideToMove());
            return d.build();
        }

        switch (action.type()) {
            case "MOVE" -> move(d, action, remaining);
            case "RESIGN" -> resign(d, action, REASON_RESIGNATION);
            case "FORFEIT" -> resign(d, action, REASON_FORFEIT);
            case "OFFER_DRAW" -> offerDraw(d, action);
            case "ACCEPT_DRAW" -> acceptDraw(d, action);
            case "DECLINE_DRAW" -> declineDraw(d, action);
            case "CLAIM_DRAW" -> claimDraw(d, action, remaining);
            default -> throw new RuleViolation("UNKNOWN_ACTION", "no handler for " + action.type());
        }
        return d.build();
    }

    /** The running clock reached zero. A stale timer (wrong phase) is ignored. */
    @Override
    public GameState onPhaseElapsed(GameState state, String endedPhase) {
        ChessState s = (ChessState) state;
        if (s.finished() || !endedPhase.equals(s.phase)) {
            return s;
        }
        ChessState.Draft d = new ChessState.Draft(s);
        flagFall(d, s.position.sideToMove());
        return d.build();
    }

    private void move(ChessState.Draft d, PlayerAction a, Long remaining) {
        Color mover = requireToMove(d, a);
        Move m = resolveMove(d.position, a);
        playMove(d, mover, m, remaining);
        if (!concludeIfOver(d, mover)) {
            nextTurn(d);
        }
    }

    private void resign(ChessState.Draft d, PlayerAction a, String reason) {
        Color color = requirePlayer(d, a);
        finish(d, color.opposite(), reason);
    }

    /** One offer per move, standing until accepted, declined, or answered with a move. */
    private void offerDraw(ChessState.Draft d, PlayerAction a) {
        Color color = requirePlayer(d, a);
        require(d.pendingDrawOffer == null, "DRAW_ALREADY_PENDING", "a draw offer is already waiting for an answer");
        int ply = d.sanMoves.size();
        require(d.lastOfferPly(color) != ply, "DRAW_ALREADY_OFFERED", "you've already offered a draw this move");
        d.pendingDrawOffer = a.actor();
        d.setLastOfferPly(color, ply);
        d.emit("DRAW_OFFERED", Map.of("by", a.actor(), "side", color.wire()));
    }

    private void acceptDraw(ChessState.Draft d, PlayerAction a) {
        requirePlayer(d, a);
        require(d.pendingDrawOffer != null && !d.pendingDrawOffer.equals(a.actor()),
                "NO_DRAW_OFFER", "your opponent hasn't offered a draw");
        draw(d, REASON_AGREEMENT);
    }

    private void declineDraw(ChessState.Draft d, PlayerAction a) {
        requirePlayer(d, a);
        require(d.pendingDrawOffer != null && !d.pendingDrawOffer.equals(a.actor()),
                "NO_DRAW_OFFER", "your opponent hasn't offered a draw");
        d.pendingDrawOffer = null;
        d.emit("DRAW_DECLINED", Map.of("by", a.actor(), "implicit", false));
    }

    /**
     * Threefold repetition or the 50-move rule, claimed by the player to move
     * (FIDE 9.2, 9.3). With no move attached the claim is about the current
     * position. With a move attached ({@code from}/{@code to}/{@code promotion})
     * the claim is about the position that move would create: if it qualifies
     * the move is played and the game drawn; if not, the claim is refused and
     * nothing is played. A move that mates or stalemates ends the game that
     * way instead — those end the game the moment they happen.
     */
    private void claimDraw(ChessState.Draft d, PlayerAction a, Long remaining) {
        Color claimant = requirePlayer(d, a);
        require(claimant == d.position.sideToMove(), "NOT_YOUR_TURN", "only the player to move can claim a draw");

        if (a.data().get("to") == null) {
            int occurrences = d.positionCounts.getOrDefault(d.position.repetitionKey(), 0);
            boolean fifty = d.position.halfmoveClock() >= FIFTY_MOVE_HALFMOVES;
            require(occurrences >= 3 || fifty, "CLAIM_INVALID",
                    "the position hasn't occurred three times and fifty moves haven't passed without a capture or pawn move");
            draw(d, occurrences >= 3 ? REASON_THREEFOLD : REASON_FIFTY_MOVES);
            return;
        }

        Move m = resolveMove(d.position, a);
        Position after = d.position.play(m);
        int priorOccurrences = after.halfmoveClock() == 0 ? 0 : d.positionCounts.getOrDefault(after.repetitionKey(), 0);
        boolean threefold = priorOccurrences + 1 >= 3;
        boolean fifty = after.halfmoveClock() >= FIFTY_MOVE_HALFMOVES;
        require(threefold || fifty, "CLAIM_INVALID",
                "that move wouldn't repeat the position a third time or complete fifty moves without a capture or pawn move");

        playMove(d, claimant, m, remaining);
        if (!concludeIfOver(d, claimant)) {
            draw(d, threefold ? REASON_THREEFOLD : REASON_FIFTY_MOVES);
        }
    }

    // ---------------------------------------------------------------- move pipeline

    /** Matches the requested move against the legal moves, with errors that say what was wrong. */
    static Move resolveMove(Position position, PlayerAction a) {
        int from = Square.parse(a.str("from"));
        int to = Square.parse(a.str("to"));
        require(from != Square.NONE && to != Square.NONE, "BAD_SQUARE", "squares are named like \"e2\"");

        Piece piece = position.at(from);
        require(piece != null && piece.color() == position.sideToMove(), "NOT_YOUR_PIECE", "you don't have a piece on " + Square.name(from));

        PieceKind promotion = parsePromotion(a.str("promotion"));
        List<Move> candidates = position.legalMovesFrom(from).stream().filter(m -> m.to() == to).toList();
        if (candidates.isEmpty()) {
            throw new RuleViolation("ILLEGAL_MOVE", position.inCheck()
                    ? "you're in check — that move doesn't get you out of it"
                    : "that's not a legal move");
        }
        boolean promotes = candidates.get(0).promotion() != null;
        if (!promotes) {
            require(promotion == null, "BAD_PROMOTION", "only a pawn reaching the last rank promotes");
            return candidates.get(0);
        }
        require(promotion != null, "PROMOTION_REQUIRED", "choose a queen, rook, bishop or knight to promote to");
        return candidates.stream()
                .filter(m -> m.promotion() == promotion)
                .findFirst()
                .orElseThrow();
    }

    private static PieceKind parsePromotion(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        PieceKind kind = switch (raw.trim().toLowerCase()) {
            case "q", "queen" -> PieceKind.QUEEN;
            case "r", "rook" -> PieceKind.ROOK;
            case "b", "bishop" -> PieceKind.BISHOP;
            case "n", "knight" -> PieceKind.KNIGHT;
            default -> null;
        };
        if (kind == null) {
            throw new RuleViolation("BAD_PROMOTION", "a pawn can only promote to a queen, rook, bishop or knight");
        }
        return kind;
    }

    private void playMove(ChessState.Draft d, Color mover, Move m, Long remaining) {
        Position before = d.position;
        String san = San.of(before, m);
        Piece moving = before.at(m.from());
        Piece captured = before.capturedBy(m);
        d.position = before.play(m);
        d.sanMoves.add(san);
        d.uciMoves.add(m.uci());
        d.lastMoveFrom = m.from();
        d.lastMoveTo = m.to();
        if (captured != null) {
            (mover == Color.WHITE ? d.capturedByWhite : d.capturedByBlack).add(captured.code());
        }

        // Bank what the server measured, then the Fischer increment for the
        // completed move. Without a stamp (no running clock) only the
        // increment applies.
        long banked = remaining != null ? remaining : d.clockMs(mover);
        d.setClockMs(mover, banked + d.config.incrementMs());

        // Moving instead of answering a pending offer declines it (FIDE 9.1.2.2).
        if (d.pendingDrawOffer != null && !d.pendingDrawOffer.equals(d.playerOf(mover))) {
            d.emit("DRAW_DECLINED", Map.of("by", d.playerOf(mover), "implicit", true));
            d.pendingDrawOffer = null;
        }
        d.countPosition();

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("side", mover.wire());
        payload.put("from", Square.name(m.from()));
        payload.put("to", Square.name(m.to()));
        payload.put("san", san);
        payload.put("uci", m.uci());
        payload.put("piece", moving.code());
        payload.put("captured", captured == null ? null : captured.code());
        payload.put("promotion", m.promotion() == null ? null : String.valueOf(m.promotion().letter()));
        payload.put("castle", m.flag() == Move.Flag.CASTLE_KINGSIDE ? "kingside"
                : m.flag() == Move.Flag.CASTLE_QUEENSIDE ? "queenside" : null);
        payload.put("enPassant", m.flag() == Move.Flag.EN_PASSANT);
        payload.put("check", d.position.inCheck());
        payload.put("fen", d.position.fen());
        payload.put("whiteMs", d.whiteClockMs);
        payload.put("blackMs", d.blackClockMs);
        d.emit("MOVE_PLAYED", payload);
    }

    /**
     * Ends the game if the move just played made it over on its own. Order
     * matters: checkmate first (it takes precedence even over the 75-move
     * rule, FIDE 9.6.2), then stalemate, then the automatic draws.
     */
    private boolean concludeIfOver(ChessState.Draft d, Color mover) {
        Position p = d.position;
        boolean noMoves = p.legalMoves().isEmpty();
        if (noMoves && p.inCheck()) {
            finish(d, mover, REASON_CHECKMATE);
        } else if (noMoves) {
            draw(d, REASON_STALEMATE);
        } else if (p.isDeadPosition()) {
            draw(d, REASON_DEAD_POSITION);
        } else if (p.halfmoveClock() >= SEVENTY_FIVE_MOVE_HALFMOVES) {
            draw(d, REASON_SEVENTY_FIVE_MOVES);
        } else if (d.positionCounts.getOrDefault(p.repetitionKey(), 0) >= 5) {
            draw(d, REASON_FIVEFOLD);
        } else {
            return false;
        }
        return true;
    }

    private void nextTurn(ChessState.Draft d) {
        Color next = d.position.sideToMove();
        d.phase = turnPhase(next);
        d.round++;
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("side", next.wire());
        payload.put("inCheck", d.position.inCheck());
        payload.put("whiteMs", d.whiteClockMs);
        payload.put("blackMs", d.blackClockMs);
        d.emit("TURN_STARTED", payload);
    }

    /**
     * The flagged side loses — unless their opponent could never checkmate
     * by any series of legal moves, in which case it's a draw (FIDE 6.9).
     */
    private void flagFall(ChessState.Draft d, Color flagged) {
        d.setClockMs(flagged, 0);
        Color opponent = flagged.opposite();
        if (d.position.canEverCheckmate(opponent)) {
            finish(d, opponent, REASON_TIMEOUT);
        } else {
            draw(d, REASON_TIMEOUT_NO_MATERIAL);
        }
    }

    private void finish(ChessState.Draft d, Color winner, String reason) {
        Map<String, String> outcome = new LinkedHashMap<>();
        outcome.put(d.white, winner == Color.WHITE ? "won" : "lost");
        outcome.put(d.black, winner == Color.BLACK ? "won" : "lost");
        conclude(d, new WinResult(winner.wire(), outcome), winner == Color.WHITE ? "1-0" : "0-1", reason);
    }

    private void draw(ChessState.Draft d, String reason) {
        Map<String, String> outcome = new LinkedHashMap<>();
        outcome.put(d.white, "tied");
        outcome.put(d.black, "tied");
        conclude(d, new WinResult("draw", outcome), "1/2-1/2", reason);
    }

    private void conclude(ChessState.Draft d, WinResult win, String score, String reason) {
        d.win = win;
        d.resultReason = reason;
        d.phase = ChessState.RESULTS;
        d.pendingDrawOffer = null;
        d.emit("GAME_OVER", Map.of(
                "winningSide", win.winningSide(),
                "result", score,
                "reason", reason,
                "whiteMs", d.whiteClockMs,
                "blackMs", d.blackClockMs));
    }

    // ---------------------------------------------------------------- clock + views

    @Override
    public OptionalLong runningClockMs(GameState state) {
        ChessState s = (ChessState) state;
        if (s.finished()) {
            return OptionalLong.empty();
        }
        return OptionalLong.of(s.clockMs(s.position.sideToMove()));
    }

    @Override
    public Optional<WinResult> checkWinCondition(GameState state) {
        return Optional.ofNullable(((ChessState) state).win);
    }

    @Override
    public Set<String> playersToAct(GameState state) {
        ChessState s = (ChessState) state;
        if (s.finished()) {
            return Set.of();
        }
        return Set.of(s.playerOf(s.position.sideToMove()));
    }

    @Override
    public PlayerVisibleState visibleStateFor(GameState state, String playerId) {
        return new PlayerVisibleState(commonView((ChessState) state));
    }

    @Override
    public PublicBroadcastState broadcastState(GameState state) {
        return new PublicBroadcastState(commonView((ChessState) state));
    }

    /** Nothing in chess is hidden, so players and spectators share one view. */
    private Map<String, Object> commonView(ChessState s) {
        Position p = s.position;
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("phase", s.phase);
        m.put("round", s.round);
        m.put("white", s.white);
        m.put("black", s.black);
        m.put("turn", p.sideToMove().wire());
        m.put("fen", p.fen());
        m.put("board", boardSnapshot(p));
        m.put("inCheck", !s.finished() && p.inCheck());
        m.put("moves", s.sanMoves);
        m.put("lastMove", s.lastMoveFrom == null ? null
                : Map.of("from", Square.name(s.lastMoveFrom), "to", Square.name(s.lastMoveTo)));
        m.put("capturedByWhite", s.capturedByWhite);
        m.put("capturedByBlack", s.capturedByBlack);
        m.put("whiteMs", s.whiteClockMs);
        m.put("blackMs", s.blackClockMs);
        m.put("incrementMs", s.config.incrementMs());
        m.put("pendingDrawOffer", s.pendingDrawOffer);
        m.put("halfmoveClock", p.halfmoveClock());
        m.put("canClaimThreefold", !s.finished() && s.repetitionCount() >= 3);
        m.put("canClaimFiftyMove", !s.finished() && p.halfmoveClock() >= FIFTY_MOVE_HALFMOVES);
        m.put("legalMoves", s.finished() ? Map.of() : legalMovesBySquare(p));
        m.put("winningSide", s.win == null ? null : s.win.winningSide());
        m.put("resultReason", s.resultReason);
        return m;
    }

    /** Board in a1..h8 order as piece codes ({@code wP}, {@code bK}); null for empty squares. */
    private static List<String> boardSnapshot(Position p) {
        List<String> out = new ArrayList<>(64);
        for (int sq = 0; sq < 64; sq++) {
            Piece piece = p.at(sq);
            out.add(piece == null ? null : piece.code());
        }
        return out;
    }

    /**
     * Server-computed destinations per origin square, so the client never
     * reimplements check, pins or castling just to highlight a tap. A
     * promotion shows its square once; the client asks which piece.
     */
    private static Map<String, List<String>> legalMovesBySquare(Position p) {
        Map<String, Set<String>> grouped = new LinkedHashMap<>();
        for (Move m : p.legalMoves()) {
            grouped.computeIfAbsent(Square.name(m.from()), k -> new LinkedHashSet<>()).add(Square.name(m.to()));
        }
        Map<String, List<String>> out = new LinkedHashMap<>();
        grouped.forEach((from, tos) -> out.put(from, List.copyOf(tos)));
        return out;
    }

    @Override
    public List<GameEvent> drainEvents(GameState prev, GameState next) {
        List<GameEvent> a = ((ChessState) prev).events();
        List<GameEvent> b = ((ChessState) next).events();
        return b.subList(a.size(), b.size());
    }

    // ---------------------------------------------------------------- helpers

    static String turnPhase(Color side) {
        return side == Color.WHITE ? ChessState.TURN_WHITE : ChessState.TURN_BLACK;
    }

    private static Color requirePlayer(ChessState.Draft d, PlayerAction a) {
        Color color = d.colorOf(a.actor());
        require(color != null, "NOT_A_PLAYER", "you're not one of the two players in this game");
        return color;
    }

    private static Color requireToMove(ChessState.Draft d, PlayerAction a) {
        Color color = requirePlayer(d, a);
        require(color == d.position.sideToMove(), "NOT_YOUR_TURN", "it's not your turn");
        return color;
    }

    private static Long clockRemaining(PlayerAction a) {
        Object raw = a.data().get(CLOCK_REMAINING_KEY);
        return raw instanceof Number n ? n.longValue() : null;
    }

    private static void require(boolean condition, String code, String message) {
        if (!condition) {
            throw new RuleViolation(code, message);
        }
    }
}
