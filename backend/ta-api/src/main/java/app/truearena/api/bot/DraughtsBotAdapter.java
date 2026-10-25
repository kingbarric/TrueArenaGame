package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import app.truearena.game.draughts.Board;
import app.truearena.game.draughts.CaptureEngine;
import app.truearena.game.draughts.Piece;
import app.truearena.game.draughts.DraughtsBotSearch;
import app.truearena.game.draughts.ScanMoveCodec;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Scan chooses complete international turns; optional captures and operational
 * failures use local search over the authoritative game reducer.
 */
public final class DraughtsBotAdapter implements GameBotAdapter {

    private static final Pattern MOVE_JSON = Pattern.compile("\\{[^}]*\"from\"\\s*:\\s*(\\d+)[^}]*\"to\"\\s*:\\s*(\\d+)[^}]*}");

    private final Piece[] board = new Piece[Board.SIZE];
    private String phase = "TurnA";
    private String playerA;
    private String playerB;
    private boolean finished;
    private boolean mandatoryCapture;
    private boolean paused;
    private Integer activeSquare;
    private long capturedSquares;
    private final DraughtsMoveSource primary;
    private final java.util.ArrayDeque<ScanMoveCodec.Move> planned = new java.util.ArrayDeque<>();
    private Piece[] expectedBoard;
    private Difficulty lastDifficulty = Difficulty.MEDIUM;

    public DraughtsBotAdapter() { this((position, side, level, budget) -> Optional.empty()); }
    public DraughtsBotAdapter(DraughtsMoveSource primary) { this.primary = primary; }

    @Override
    public String gameType() {
        return "draughts";
    }

    @Override
    public Optional<BotPrompt> onFrame(String frameType, Map<String, Object> payload, String botUserId, Difficulty difficulty) {
        switch (frameType) {
            case "SNAPSHOT" -> applyFullView(payload);
            case "EVENT" -> applyEvent(payload);
            // A bare PHASE frame arrives BEFORE the domain EVENTs that describe what
            // just happened (see GameOrchestrator.afterMutation: broadcastPhase() runs
            // synchronously while event persistence/broadcast is still a pending Mono).
            // Track the phase name for turnSide(), but never decide a move off it —
            // our local `board` may still be missing the opponent's just-played move.
            // Only act once an EVENT (or a fresh SNAPSHOT) has caught us up.
            case "PHASE" -> {
                phase = String.valueOf(payload.get("phase"));
                return Optional.empty();
            }
            default -> { /* ERROR and anything else: nothing to update here */ }
        }
        if ("EVENT".equals(frameType)) {
            String event = String.valueOf(payload.get("type"));
            if (!List.of("GAME_STARTED", "TURN_STARTED", "GAME_RESUMED").contains(event)
                    && !("PIECE_CAPTURED".equals(event) && activeSquare != null)) return Optional.empty();
        }
        if (paused || finished || playerA == null || playerB == null) {
            return Optional.empty();
        }
        String mySide = sideOf(botUserId);
        if (mySide == null || !mySide.equals(turnSide())) {
            return Optional.empty();
        }
        return Optional.of(buildPrompt(mySide, difficulty));
    }

    @SuppressWarnings("unchecked")
    private void applyFullView(Map<String, Object> p) {
        Object ph = p.get("phase");
        if (ph != null) phase = String.valueOf(ph);
        finished = "Results".equals(phase);
        paused = Boolean.TRUE.equals(p.get("paused"));
        mandatoryCapture = Boolean.TRUE.equals(p.get("mandatoryCapture"));
        if (!mandatoryCapture) planned.clear();
        activeSquare = p.get("activeSquare") instanceof Number n ? n.intValue() : null;
        capturedSquares = 0;
        if (p.get("capturedSquares") instanceof List<?> squares)
            for (Object square : squares) if (square instanceof Number n && n.intValue() >= 0 && n.intValue() < Board.SIZE)
                capturedSquares |= 1L << n.intValue();
        Object a = p.get("playerA");
        if (a != null) playerA = String.valueOf(a);
        Object b = p.get("playerB");
        if (b != null) playerB = String.valueOf(b);
        Object rawBoard = p.get("board");
        if (rawBoard instanceof List<?> list) {
            applyBoardSnapshot((List<Object>) list);
        }
    }

    private void applyBoardSnapshot(List<Object> raw) {
        for (int i = 0; i < Board.SIZE && i < raw.size(); i++) {
            Object v = raw.get(i);
            board[i] = v == null ? null : Piece.valueOf(String.valueOf(v));
        }
    }

    @SuppressWarnings("unchecked")
    private void applyEvent(Map<String, Object> payload) {
        String type = String.valueOf(payload.get("type"));
        Map<String, Object> data = (Map<String, Object>) payload.getOrDefault("data", Map.of());
        switch (type) {
            case "GAME_STARTED" -> {
                planned.clear(); capturedSquares = 0; finished = false;
                if (data.containsKey("mandatoryCapture")) mandatoryCapture = Boolean.TRUE.equals(data.get("mandatoryCapture"));
                playerA = String.valueOf(data.get("playerA"));
                playerB = String.valueOf(data.get("playerB"));
                Object rawBoard = data.get("board");
                if (rawBoard instanceof List<?> list) applyBoardSnapshot((List<Object>) list);
            }
            case "PIECE_MOVED" -> {
                int from = intOf(data.get("from")), to = intOf(data.get("to"));
                board[to] = board[from];
                board[from] = null;
            }
            case "PIECE_CAPTURED" -> {
                int from = intOf(data.get("from")), to = intOf(data.get("to")), captured = intOf(data.get("captured"));
                board[to] = board[from];
                board[from] = null;
                board[captured] = null;
                capturedSquares |= 1L << captured;
                activeSquare = String.valueOf(data.get("side")).equals(turnSide())
                        && !CaptureEngine.captureLandings(board, to, capturedSquares).isEmpty() ? to : null;
            }
            case "PIECE_PROMOTED" -> {
                int sq = intOf(data.get("square"));
                String side = String.valueOf(data.get("side"));
                board[sq] = "A".equals(side) ? Piece.A_KING : Piece.B_KING;
            }
            case "GAME_OVER" -> finished = true;
            case "TURN_STARTED" -> { activeSquare = null; capturedSquares = 0; planned.clear(); }
            case "UNDO_ACCEPTED" -> {
                if (data.get("board") instanceof List<?> list) applyBoardSnapshot((List<Object>) list);
                activeSquare = null;
                capturedSquares = 0; planned.clear();
            }
            case "GAME_PAUSED" -> paused = true;
            case "GAME_RESUMED" -> paused = false;
            default -> { /* TURN_STARTED needs no local state beyond `phase`, which PHASE frames already carry */ }
        }
    }

    private static int intOf(Object o) {
        return o instanceof Number n ? n.intValue() : Integer.parseInt(String.valueOf(o));
    }

    private String sideOf(String playerId) {
        if (playerId.equals(playerA)) return "A";
        if (playerId.equals(playerB)) return "B";
        return null;
    }

    private String turnSide() {
        return "TurnA".equals(phase) ? "A" : "TurnB".equals(phase) ? "B" : null;
    }

    private BotPrompt buildPrompt(String mySide, Difficulty difficulty) {
        int required = !mandatoryCapture ? 0 : activeSquare == null ? CaptureEngine.requiredCaptureCount(board, mySide)
                : CaptureEngine.maxCaptureCount(board, activeSquare, capturedSquares);
        List<int[]> legalMoves = new ArrayList<>(); // {from, to}
        for (int sq = 0; sq < Board.SIZE; sq++) {
            if (board[sq] == null || !board[sq].side().equals(mySide)) continue;
            if (activeSquare != null && sq != activeSquare) continue;
            if (required > 0) {
                for (CaptureEngine.Landing l : CaptureEngine.captureLandings(board, sq, capturedSquares)) {
                    Piece[] after = CaptureEngine.applyCapture(board, sq, l);
                    if (1 + CaptureEngine.maxCaptureCount(after, l.to(), capturedSquares | (1L << l.captured())) == required) {
                        legalMoves.add(new int[]{sq, l.to()});
                    }
                }
            } else {
                if (activeSquare == null) for (int to : CaptureEngine.simpleLandings(board, sq)) legalMoves.add(new int[]{sq, to});
                for (CaptureEngine.Landing l : CaptureEngine.captureLandings(board, sq, capturedSquares)) legalMoves.add(new int[]{sq, l.to()});
            }
        }

        StringBuilder boardText = new StringBuilder();
        for (int sq = 0; sq < Board.SIZE; sq++) {
            Piece p = board[sq];
            boardText.append(sq).append(':').append(p == null ? "empty" : p.name()).append(' ');
        }
        StringBuilder movesText = new StringBuilder();
        for (int[] m : legalMoves) {
            movesText.append('{').append(m[0]).append("->").append(m[1]).append("} ");
        }

        String system = """
                You are playing International Draughts (10x10, 20 pieces per side) as side %s.
                Squares are numbered 0-49; row 0 is side A's back row, row 9 is side B's.
                %s
                Reply with ONLY a JSON object of the exact shape {"from": <square>, "to": <square>} \
                naming one of the legal moves listed — no other text.""".formatted(
                mySide,
                switch (difficulty) {
                    case EASY -> "Play a reasonable move.";
                    case MEDIUM -> "Prefer capturing when possible, protect your back row, and advance toward promotion.";
                    case HARD -> "Think a few moves ahead: prioritize capture sequences, king safety, board control, "
                            + "and avoid moves that hang a piece to a follow-up capture.";
                });
        String user = (required > 0
                ? "A capture is mandatory this turn. "
                : "Choose any legal move. ")
                + "Board: " + boardText + ". Legal moves: " + movesText;
        return new BotPrompt(system, user);
    }

    @Override
    public Optional<PlayerAction> parseAction(String rawResponse, String botUserId) {
        if (rawResponse == null || rawResponse.isBlank()) {
            return Optional.empty();
        }
        Matcher m = MOVE_JSON.matcher(rawResponse);
        if (!m.find()) {
            return Optional.empty();
        }
        int from = Integer.parseInt(m.group(1));
        int to = Integer.parseInt(m.group(2));
        return Optional.of(PlayerAction.of(botUserId, "MOVE", Map.of("from", from, "to", to)));
    }

    @Override
    public Optional<PlayerAction> fallbackAction(String botUserId) {
        planned.clear();
        return localMove(botUserId, lastDifficulty);
    }

    @Override public Optional<PlayerAction> decideLocally(String botUserId, Difficulty difficulty) {
        lastDifficulty = difficulty;
        String mySide = sideOf(botUserId);
        if (mySide == null || finished || paused || !mySide.equals(turnSide())) {
            return Optional.empty();
        }
        var continuation = nextPlanned(botUserId);
        if (continuation.isPresent()) return continuation;
        if (mandatoryCapture && activeSquare == null) {
            long budget = difficulty == Difficulty.EASY ? 150 : difficulty == Difficulty.MEDIUM ? 450 : 1300;
            primary.choose(board.clone(), mySide, difficulty, budget).ifPresent(moves -> {
                planned.addAll(moves); expectedBoard = board.clone();
            });
            var move = nextPlanned(botUserId);
            if (move.isPresent()) return move;
        }
        if (Thread.currentThread().isInterrupted()) return Optional.empty();
        return localMove(botUserId, difficulty);
    }

    private Optional<PlayerAction> localMove(String botUserId, Difficulty difficulty) {
        if (finished || paused || !java.util.Objects.equals(sideOf(botUserId), turnSide()) || sideOf(botUserId) == null)
            return Optional.empty();
        int depth = difficulty == Difficulty.EASY ? 1 : difficulty == Difficulty.MEDIUM ? 3 : 5;
        long millis = difficulty == Difficulty.EASY ? 30 : difficulty == Difficulty.MEDIUM ? 100 : 250;
        return DraughtsBotSearch.choose(board, playerA, playerB, botUserId, activeSquare, capturedSquares,
                mandatoryCapture, depth, millis);
    }

    private Optional<PlayerAction> nextPlanned(String player) {
        if (planned.isEmpty()) return Optional.empty();
        ScanMoveCodec.Move move = planned.removeFirst();
        int from = move.from(), to = move.to();
        if (!mandatoryCapture || !java.util.Arrays.equals(board, expectedBoard) || from < 0 || from >= Board.SIZE
                || to < 0 || to >= Board.SIZE || board[from] == null || !board[from].side().equals(sideOf(player))
                || (activeSquare != null && activeSquare != from)) { planned.clear(); return Optional.empty(); }
        var landing = CaptureEngine.captureLandings(board, from, capturedSquares).stream().filter(l -> l.to() == to).findFirst();
        int required = activeSquare == null ? CaptureEngine.requiredCaptureCount(board, sideOf(player))
                : CaptureEngine.maxCaptureCount(board, from, capturedSquares);
        boolean legal = required == 0 ? CaptureEngine.simpleLandings(board, from).contains(to)
                : landing.isPresent() && 1 + CaptureEngine.maxCaptureCount(CaptureEngine.applyCapture(board, from, landing.get()), to,
                        capturedSquares | (1L << landing.get().captured())) == required;
        if (!legal) { planned.clear(); return Optional.empty(); }
        expectedBoard = landing.isPresent() ? CaptureEngine.applyCapture(board, from, landing.get())
                : CaptureEngine.applySimpleMove(board, from, to);
        return Optional.of(PlayerAction.of(player, "MOVE", Map.of("from", from, "to", to)));
    }
}
