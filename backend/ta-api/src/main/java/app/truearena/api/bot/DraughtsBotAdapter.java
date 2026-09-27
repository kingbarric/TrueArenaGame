package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import app.truearena.game.draughts.Board;
import app.truearena.game.draughts.CaptureEngine;
import app.truearena.game.draughts.Piece;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Draughts' bot adapter — the first (and so far only) implementation of
 * {@link GameBotAdapter}. Reuses the real {@code ta-game-draughts} rules
 * engine directly (this runs in the same JVM as the server, unlike the
 * Flutter client's separate Dart port for UI highlighting) — no rules
 * duplicated a third time.
 */
public final class DraughtsBotAdapter implements GameBotAdapter {

    private static final SecureRandom RNG = new SecureRandom();
    private static final Pattern MOVE_JSON = Pattern.compile("\\{[^}]*\"from\"\\s*:\\s*(\\d+)[^}]*\"to\"\\s*:\\s*(\\d+)[^}]*}");

    private final Piece[] board = new Piece[Board.SIZE];
    private String phase = "TurnA";
    private String playerA;
    private String playerB;
    private boolean finished;

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
        if (finished || playerA == null || playerB == null) {
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
            }
            case "PIECE_PROMOTED" -> {
                int sq = intOf(data.get("square"));
                String side = String.valueOf(data.get("side"));
                board[sq] = "A".equals(side) ? Piece.A_KING : Piece.B_KING;
            }
            case "GAME_OVER" -> finished = true;
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
        int required = CaptureEngine.requiredCaptureCount(board, mySide);
        List<int[]> legalMoves = new ArrayList<>(); // {from, to}
        for (int sq = 0; sq < Board.SIZE; sq++) {
            if (board[sq] == null || !board[sq].side().equals(mySide)) continue;
            if (required > 0) {
                for (CaptureEngine.Landing l : CaptureEngine.captureLandings(board, sq)) {
                    Piece[] after = CaptureEngine.applyCapture(board, sq, l);
                    if (1 + CaptureEngine.maxCaptureCount(after, l.to()) == required) {
                        legalMoves.add(new int[]{sq, l.to()});
                    }
                }
            } else {
                for (int to : CaptureEngine.simpleLandings(board, sq)) {
                    legalMoves.add(new int[]{sq, to});
                }
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
                : "No capture is available. ")
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
        String mySide = sideOf(botUserId);
        if (mySide == null) {
            return Optional.empty();
        }
        int required = CaptureEngine.requiredCaptureCount(board, mySide);
        List<int[]> candidates = new ArrayList<>();
        for (int sq = 0; sq < Board.SIZE; sq++) {
            if (board[sq] == null || !board[sq].side().equals(mySide)) continue;
            if (required > 0) {
                for (CaptureEngine.Landing l : CaptureEngine.captureLandings(board, sq)) {
                    Piece[] after = CaptureEngine.applyCapture(board, sq, l);
                    if (1 + CaptureEngine.maxCaptureCount(after, l.to()) == required) {
                        candidates.add(new int[]{sq, l.to()});
                    }
                }
            } else {
                for (int to : CaptureEngine.simpleLandings(board, sq)) {
                    candidates.add(new int[]{sq, to});
                }
            }
        }
        if (candidates.isEmpty()) {
            return Optional.empty();
        }
        int[] pick = candidates.get(RNG.nextInt(candidates.size()));
        return Optional.of(PlayerAction.of(botUserId, "MOVE", Map.of("from", pick[0], "to", pick[1])));
    }
}
