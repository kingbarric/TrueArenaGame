package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import app.truearena.game.chess.ChessEngine;
import app.truearena.game.chess.Move;
import app.truearena.game.chess.Position;
import app.truearena.game.chess.Square;

import java.security.SecureRandom;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ThreadLocalRandom;

/**
 * The chess Cyber Agent. Unlike the other games' agents it never asks a
 * language model for a move — models play chess badly and slowly — but
 * searches with {@link ChessEngine} on the real rules engine.
 *
 * <p>It reads the server's own view of the game: chess pushes every player
 * a full snapshot after each move ({@code ChessModule.hasPrivatePlayerState}),
 * so the agent acts on snapshots alone and never has to replay events.
 *
 * <p>It spends its own clock carefully: a slice of what's left plus most of
 * the increment, so a bullet game can't be lost on time by "thinking".
 */
public final class ChessBotAdapter implements GameBotAdapter {

    private enum Pending { NONE, MOVE, ANSWER_DRAW }

    private final ChessEngine engine = new ChessEngine(new SecureRandom());

    private String white;
    private String black;
    private String turn = "white";
    private Position position = Position.initial();
    private boolean finished;
    private boolean paused;
    private int ply;
    private String pendingDrawOffer;
    private boolean canClaimDraw;
    private long whiteMs;
    private long blackMs;
    private long incrementMs;
    private Long liveClockMs;
    private final Set<String> history = new HashSet<>();

    /** The ply this agent last moved on, and the offer it last answered — never act twice on one. */
    private int movedOnPly = -1;
    private int answeredOfferOnPly = -1;
    private Pending pending = Pending.NONE;

    /** Off in tests, where a believable pause is just a slow test. */
    boolean pacing = true;

    /** Lowered in tests so a whole game searches in a blink. */
    long thinkCapMs = Long.MAX_VALUE;

    @Override
    public String gameType() {
        return "chess";
    }

    @Override
    public boolean decidesLocally() {
        return true;
    }

    @Override
    @SuppressWarnings("unchecked")
    public Optional<BotPrompt> onFrame(String frameType, Map<String, Object> payload, String botUserId, Difficulty difficulty) {
        if ("EVENT".equals(frameType)) {
            String type = String.valueOf(payload.get("type"));
            if ("GAME_PAUSED".equals(type)) {
                paused = true;
                return Optional.empty();
            }
            if (!"GAME_RESUMED".equals(type)) {
                return Optional.empty();
            }
            paused = false;
            // A move tried while paused was refused, and resuming brings no
            // fresh snapshot — so if it's still our turn, take it again.
            if (white != null && myTurn(botUserId)) {
                movedOnPly = -1;
            }
        } else if (!"SNAPSHOT".equals(frameType) || Boolean.TRUE.equals(payload.get("lobby"))) {
            return Optional.empty();
        } else {
            apply(payload);
        }
        pending = Pending.NONE;
        if (paused || finished || white == null || black == null) {
            return Optional.empty();
        }
        String mySide = sideOf(botUserId);
        if (mySide == null) {
            return Optional.empty();
        }
        if (pendingDrawOffer != null && !pendingDrawOffer.equals(botUserId) && answeredOfferOnPly != ply) {
            pending = Pending.ANSWER_DRAW;
        } else if (mySide.equals(turn) && movedOnPly != ply) {
            pending = Pending.MOVE;
        } else {
            return Optional.empty();
        }
        return Optional.of(new BotPrompt("", ""));
    }

    @SuppressWarnings("unchecked")
    private void apply(Map<String, Object> p) {
        white = stringOr(p.get("white"), white);
        black = stringOr(p.get("black"), black);
        turn = stringOr(p.get("turn"), turn);
        finished = "Results".equals(p.get("phase"));
        Object fen = p.get("fen");
        if (fen != null) {
            position = Position.fromFen(String.valueOf(fen));
            history.add(position.repetitionKey());
        }
        if (p.get("moves") instanceof List<?> moves) {
            ply = moves.size();
        }
        pendingDrawOffer = p.get("pendingDrawOffer") == null ? null : String.valueOf(p.get("pendingDrawOffer"));
        canClaimDraw = Boolean.TRUE.equals(p.get("canClaimThreefold")) || Boolean.TRUE.equals(p.get("canClaimFiftyMove"));
        whiteMs = longOr(p.get("whiteMs"), whiteMs);
        blackMs = longOr(p.get("blackMs"), blackMs);
        incrementMs = longOr(p.get("incrementMs"), incrementMs);
        liveClockMs = p.get("clockMsLeft") instanceof Number n ? n.longValue() : null;
        paused = Boolean.TRUE.equals(p.get("paused"));
    }

    @Override
    public Optional<PlayerAction> decideLocally(String botUserId, Difficulty difficulty) {
        return switch (pending) {
            case ANSWER_DRAW -> {
                answeredOfferOnPly = ply;
                // Take a draw only when the position is going against us.
                boolean worse = ChessEngine.evaluate(position) * (myTurn(botUserId) ? 1 : -1) <= -150;
                yield Optional.of(PlayerAction.of(botUserId, worse ? "ACCEPT_DRAW" : "DECLINE_DRAW", Map.of()));
            }
            case MOVE -> move(botUserId, difficulty, pacing);
            case NONE -> Optional.empty();
        };
    }

    private Optional<PlayerAction> move(String botUserId, Difficulty difficulty, boolean paced) {
        if (!myTurn(botUserId) || finished) {
            return Optional.empty();
        }
        movedOnPly = ply;
        if (canClaimDraw && ChessEngine.evaluate(position) <= -50) {
            return Optional.of(PlayerAction.of(botUserId, "CLAIM_DRAW", Map.of()));
        }
        long clock = myClockMs(botUserId);
        long budget = Math.min(thinkCapMs, Math.max(100, clock / 30 + incrementMs * 3 / 4));
        long started = System.currentTimeMillis();
        Optional<ChessEngine.Result> result = engine.choose(position, history, levelFor(difficulty), budget);
        if (result.isEmpty()) {
            return Optional.empty();
        }
        if (paced) {
            pace(difficulty, System.currentTimeMillis() - started, clock);
        }
        Move m = result.get().move();
        Map<String, Object> data = new HashMap<>();
        data.put("from", Square.name(m.from()));
        data.put("to", Square.name(m.to()));
        if (m.promotion() != null) {
            data.put("promotion", String.valueOf(m.promotion().letter()));
        }
        return Optional.of(PlayerAction.of(botUserId, "MOVE", data));
    }

    /**
     * A person doesn't reply in four milliseconds. Pad a quick search out to
     * a believable pause — but never by more than a sliver of the clock.
     */
    private static void pace(Difficulty difficulty, long spentMs, long clockMs) {
        int target = switch (difficulty) {
            case EASY -> ThreadLocalRandom.current().nextInt(700, 1600);
            case MEDIUM -> ThreadLocalRandom.current().nextInt(800, 1900);
            case HARD -> ThreadLocalRandom.current().nextInt(600, 1500);
        };
        long pad = Math.min(target - spentMs, clockMs / 40);
        if (pad > 0) {
            try {
                Thread.sleep(pad);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    static ChessEngine.Level levelFor(Difficulty difficulty) {
        return switch (difficulty) {
            case EASY -> ChessEngine.Level.AMATEUR;
            case MEDIUM -> ChessEngine.Level.PRO;
            case HARD -> ChessEngine.Level.LEGEND;
        };
    }

    private long myClockMs(String botUserId) {
        if (myTurn(botUserId) && liveClockMs != null) {
            return liveClockMs;
        }
        return botUserId.equals(white) ? whiteMs : blackMs;
    }

    private boolean myTurn(String botUserId) {
        return turn.equals(sideOf(botUserId));
    }

    private String sideOf(String playerId) {
        if (playerId.equals(white)) return "white";
        if (playerId.equals(black)) return "black";
        return null;
    }

    @Override
    public Optional<PlayerAction> parseAction(String rawResponse, String botUserId) {
        return Optional.empty(); // never asks a model
    }

    /** A quick, unpaced move — used when the server rejected something and the game mustn't stall. */
    @Override
    public Optional<PlayerAction> fallbackAction(String botUserId) {
        if (!myTurn(botUserId) || finished) {
            return Optional.empty();
        }
        Position p = position;
        List<Move> legal = p.legalMoves();
        if (legal.isEmpty()) {
            return Optional.empty();
        }
        movedOnPly = -1;
        return move(botUserId, Difficulty.EASY, false);
    }

    private static String stringOr(Object v, String fallback) {
        return v == null ? fallback : String.valueOf(v);
    }

    private static long longOr(Object v, long fallback) {
        return v instanceof Number n ? n.longValue() : fallback;
    }
}
