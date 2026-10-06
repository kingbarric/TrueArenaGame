package app.truearena.game.chess;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Random;
import java.util.Set;

/**
 * The Cyber Agent's chess brain: iterative-deepening negamax with
 * alpha-beta pruning, a capture-only quiescence search so it doesn't stop
 * thinking in the middle of an exchange, and a material plus
 * piece-square-table evaluation.
 *
 * <p>It plays on the same {@link Position} the rules engine uses, so every
 * move it considers is legal by construction — there is no second move
 * generator to drift out of step with the rules.
 *
 * <p>Strength is set by {@link Level}: how deep it may look, how long it may
 * think, and how willing it is to pick a move that isn't quite the best.
 * The weaker levels are deliberately imperfect so they can be beaten.
 */
public final class ChessEngine {

    /** How strong to play. */
    public enum Level {
        /** Looks two moves ahead and often settles for a decent move rather than the best. */
        AMATEUR(2, 400, 120, 0.12),
        /** Looks three moves ahead, with a little variety among near-equal moves. */
        PRO(3, 1200, 25, 0.0),
        /** Searches as deep as its time allows and always plays its best move. */
        LEGEND(64, 3000, 0, 0.0);

        final int maxDepth;
        final long maxThinkMs;
        /** Moves scoring within this many centipawns of the best are all candidates. */
        final int slackCp;
        /** Chance of playing any legal move at all, the way a beginner sometimes does. */
        final double wildChance;

        Level(int maxDepth, long maxThinkMs, int slackCp, double wildChance) {
            this.maxDepth = maxDepth;
            this.maxThinkMs = maxThinkMs;
            this.slackCp = slackCp;
            this.wildChance = wildChance;
        }
    }

    /** What the engine decided, and what it thinks of the position (centipawns, mover's view). */
    public record Result(Move move, int score, int depth) {
    }

    static final int MATE = 100_000;
    private static final int INF = 1_000_000;
    private static final int[] VALUE = {100, 320, 330, 500, 900, 0};
    private static final int MAX_QUIESCENCE = 8;

    private final Random random;
    private long deadline;
    private boolean outOfTime;
    private long nodes;

    public ChessEngine(Random random) {
        this.random = random;
    }

    /**
     * Picks a move for the side to move.
     *
     * @param history repetition keys of positions already reached in the
     *                game, so the engine knows which lines repeat
     * @param budgetMs the most it may think, before the level's own cap
     * @return empty only when the side to move has no legal move
     */
    public java.util.Optional<Result> choose(Position position, Set<String> history, Level level, long budgetMs) {
        List<Move> legal = position.legalMoves();
        if (legal.isEmpty()) {
            return java.util.Optional.empty();
        }
        if (legal.size() == 1) {
            return java.util.Optional.of(new Result(legal.get(0), evaluate(position), 0));
        }
        if (level.wildChance > 0 && random.nextDouble() < level.wildChance) {
            Move m = legal.get(random.nextInt(legal.size()));
            return java.util.Optional.of(new Result(m, evaluate(position), 0));
        }

        long think = Math.max(50, Math.min(budgetMs, level.maxThinkMs));
        deadline = System.currentTimeMillis() + think;
        outOfTime = false;
        nodes = 0;

        Set<String> path = new HashSet<>(history);
        List<Move> order = orderMoves(position, legal, null);
        List<Scored> completed = null;
        int completedDepth = 0;

        for (int depth = 1; depth <= level.maxDepth; depth++) {
            List<Scored> scored = searchRoot(position, order, depth, path, level.slackCp > 0);
            if (outOfTime) {
                break;
            }
            completed = scored;
            completedDepth = depth;
            order = scored.stream().map(Scored::move).toList();
            if (Math.abs(scored.get(0).score) >= MATE - 100) {
                break; // a forced mate either way: looking deeper changes nothing
            }
        }
        if (completed == null) {
            // Not even depth 1 finished — take the best-looking move by ordering.
            return java.util.Optional.of(new Result(order.get(0), evaluate(position), 0));
        }

        int best = completed.get(0).score;
        List<Scored> candidates = new ArrayList<>();
        for (Scored s : completed) {
            if (s.score >= best - level.slackCp) {
                candidates.add(s);
            }
        }
        // With no slack, the first entry is the one that actually earned the
        // best score; later ties are only bounds from pruned searches.
        Scored pick = level.slackCp == 0 ? completed.get(0) : candidates.get(random.nextInt(candidates.size()));
        return java.util.Optional.of(new Result(pick.move, pick.score, completedDepth));
    }

    long nodes() {
        return nodes;
    }

    private record Scored(Move move, int score) {
    }

    /**
     * Scores every root move. With {@code exact} each gets a full window, so
     * near-equal moves can be told apart for the weaker levels' variety; the
     * strongest level only needs the best one and can prune the rest.
     */
    private List<Scored> searchRoot(Position position, List<Move> order, int depth, Set<String> path, boolean exact) {
        List<Scored> out = new ArrayList<>(order.size());
        int alpha = -INF;
        for (Move m : order) {
            Position next = position.play(m);
            String key = next.repetitionKey();
            boolean added = path.add(key);
            int score = !added
                    ? 0 // straight back into a position the game has seen
                    : -negamax(next, depth - 1, -INF, exact ? INF : -alpha, 1, path);
            if (added) {
                path.remove(key);
            }
            if (outOfTime) {
                return out;
            }
            out.add(new Scored(m, score));
            alpha = Math.max(alpha, score);
        }
        out.sort(Comparator.comparingInt(Scored::score).reversed());
        return out;
    }

    private int negamax(Position pos, int depth, int alpha, int beta, int ply, Set<String> path) {
        if ((++nodes & 1023) == 0 && System.currentTimeMillis() > deadline) {
            outOfTime = true;
        }
        if (outOfTime) {
            return 0;
        }
        if (pos.halfmoveClock() >= 100 || pos.isDeadPosition()) {
            return 0;
        }
        List<Move> legal = pos.legalMoves();
        if (legal.isEmpty()) {
            return pos.inCheck() ? -(MATE - ply) : 0;
        }
        if (depth <= 0) {
            return quiescence(pos, alpha, beta, 0);
        }
        int best = -INF;
        for (Move m : orderMoves(pos, legal, null)) {
            Position next = pos.play(m);
            String key = next.repetitionKey();
            int score;
            if (!path.add(key)) {
                score = 0; // repeating a position: call it level
            } else {
                score = -negamax(next, depth - 1, -beta, -alpha, ply + 1, path);
                path.remove(key);
            }
            if (score > best) {
                best = score;
            }
            if (score > alpha) {
                alpha = score;
            }
            if (alpha >= beta) {
                break;
            }
        }
        return best;
    }

    /** Keeps searching captures and promotions until the position is quiet, so it never stops mid-exchange. */
    private int quiescence(Position pos, int alpha, int beta, int qdepth) {
        if ((++nodes & 1023) == 0 && System.currentTimeMillis() > deadline) {
            outOfTime = true;
        }
        if (outOfTime) {
            return 0;
        }
        int standPat = evaluate(pos);
        if (standPat >= beta) {
            return standPat;
        }
        if (standPat > alpha) {
            alpha = standPat;
        }
        if (qdepth >= MAX_QUIESCENCE) {
            return standPat;
        }
        List<Move> noisy = new ArrayList<>();
        for (Move m : pos.legalMoves()) {
            if (pos.capturedBy(m) != null || m.promotion() == PieceKind.QUEEN) {
                noisy.add(m);
            }
        }
        for (Move m : orderMoves(pos, noisy, null)) {
            int score = -quiescence(pos.play(m), -beta, -alpha, qdepth + 1);
            if (score >= beta) {
                return score;
            }
            if (score > alpha) {
                alpha = score;
            }
        }
        return alpha;
    }

    /** Best captures first (most valuable victim, cheapest attacker), then promotions, then the rest. */
    private static List<Move> orderMoves(Position pos, List<Move> moves, Move first) {
        List<Move> sorted = new ArrayList<>(moves);
        sorted.sort(Comparator.comparingInt((Move m) -> -orderScore(pos, m, first)));
        return sorted;
    }

    private static int orderScore(Position pos, Move m, Move first) {
        if (m.equals(first)) {
            return 1_000_000;
        }
        int score = 0;
        Piece victim = pos.capturedBy(m);
        if (victim != null) {
            score += 10_000 + 10 * VALUE[victim.kind().ordinal()] - VALUE[pos.at(m.from()).kind().ordinal()] / 10;
        }
        if (m.promotion() != null) {
            score += 8_000 + VALUE[m.promotion().ordinal()];
        }
        if (m.isCastle()) {
            score += 50;
        }
        return score;
    }

    // ---------------------------------------------------------------- eval

    /** Static evaluation in centipawns from the side to move's point of view. */
    public static int evaluate(Position pos) {
        int mg = 0;
        int nonPawnMaterial = 0;
        int whiteBishops = 0;
        int blackBishops = 0;
        for (int sq = 0; sq < 64; sq++) {
            Piece p = pos.at(sq);
            if (p == null || p.kind() == PieceKind.KING) {
                continue;
            }
            if (p.kind() != PieceKind.PAWN) {
                nonPawnMaterial += VALUE[p.kind().ordinal()];
            }
            if (p.kind() == PieceKind.BISHOP) {
                if (p.color() == Color.WHITE) whiteBishops++;
                else blackBishops++;
            }
        }
        boolean endgame = nonPawnMaterial <= 2600;
        for (int sq = 0; sq < 64; sq++) {
            Piece p = pos.at(sq);
            if (p == null) {
                continue;
            }
            // Tables are written from White's side, a8 first; mirror for Black.
            int idx = p.color() == Color.WHITE
                    ? (7 - Square.rank(sq)) * 8 + Square.file(sq)
                    : Square.rank(sq) * 8 + Square.file(sq);
            int v = VALUE[p.kind().ordinal()] + table(p.kind(), endgame)[idx];
            mg += p.color() == Color.WHITE ? v : -v;
        }
        if (whiteBishops >= 2) mg += 30;
        if (blackBishops >= 2) mg -= 30;
        return pos.sideToMove() == Color.WHITE ? mg : -mg;
    }

    private static int[] table(PieceKind kind, boolean endgame) {
        return switch (kind) {
            case PAWN -> PAWN_T;
            case KNIGHT -> KNIGHT_T;
            case BISHOP -> BISHOP_T;
            case ROOK -> ROOK_T;
            case QUEEN -> QUEEN_T;
            case KING -> endgame ? KING_END_T : KING_MID_T;
        };
    }

    // Simplified evaluation tables (Tomasz Michniewski), White's view, rank 8 first.
    private static final int[] PAWN_T = {
            0, 0, 0, 0, 0, 0, 0, 0,
            50, 50, 50, 50, 50, 50, 50, 50,
            10, 10, 20, 30, 30, 20, 10, 10,
            5, 5, 10, 25, 25, 10, 5, 5,
            0, 0, 0, 20, 20, 0, 0, 0,
            5, -5, -10, 0, 0, -10, -5, 5,
            5, 10, 10, -20, -20, 10, 10, 5,
            0, 0, 0, 0, 0, 0, 0, 0};
    private static final int[] KNIGHT_T = {
            -50, -40, -30, -30, -30, -30, -40, -50,
            -40, -20, 0, 0, 0, 0, -20, -40,
            -30, 0, 10, 15, 15, 10, 0, -30,
            -30, 5, 15, 20, 20, 15, 5, -30,
            -30, 0, 15, 20, 20, 15, 0, -30,
            -30, 5, 10, 15, 15, 10, 5, -30,
            -40, -20, 0, 5, 5, 0, -20, -40,
            -50, -40, -30, -30, -30, -30, -40, -50};
    private static final int[] BISHOP_T = {
            -20, -10, -10, -10, -10, -10, -10, -20,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -10, 0, 5, 10, 10, 5, 0, -10,
            -10, 5, 5, 10, 10, 5, 5, -10,
            -10, 0, 10, 10, 10, 10, 0, -10,
            -10, 10, 10, 10, 10, 10, 10, -10,
            -10, 5, 0, 0, 0, 0, 5, -10,
            -20, -10, -10, -10, -10, -10, -10, -20};
    private static final int[] ROOK_T = {
            0, 0, 0, 0, 0, 0, 0, 0,
            5, 10, 10, 10, 10, 10, 10, 5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            -5, 0, 0, 0, 0, 0, 0, -5,
            0, 0, 0, 5, 5, 0, 0, 0};
    private static final int[] QUEEN_T = {
            -20, -10, -10, -5, -5, -10, -10, -20,
            -10, 0, 0, 0, 0, 0, 0, -10,
            -10, 0, 5, 5, 5, 5, 0, -10,
            -5, 0, 5, 5, 5, 5, 0, -5,
            0, 0, 5, 5, 5, 5, 0, -5,
            -10, 5, 5, 5, 5, 5, 0, -10,
            -10, 0, 5, 0, 0, 0, 0, -10,
            -20, -10, -10, -5, -5, -10, -10, -20};
    private static final int[] KING_MID_T = {
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -20, -30, -30, -40, -40, -30, -30, -20,
            -10, -20, -20, -20, -20, -20, -20, -10,
            20, 20, 0, 0, 0, 0, 20, 20,
            20, 30, 10, 0, 0, 10, 30, 20};
    private static final int[] KING_END_T = {
            -50, -40, -30, -20, -20, -30, -40, -50,
            -30, -20, -10, 0, 0, -10, -20, -30,
            -30, -10, 20, 30, 30, 20, -10, -30,
            -30, -10, 30, 40, 40, 30, -10, -30,
            -30, -10, 30, 40, 40, 30, -10, -30,
            -30, -10, 20, 30, 30, 20, -10, -30,
            -30, -30, 0, 0, 0, 0, -30, -30,
            -50, -30, -30, -30, -30, -30, -30, -50};
}
