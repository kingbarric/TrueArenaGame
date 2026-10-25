package app.truearena.game.draughts;

import app.truearena.engine.PlayerAction;
import app.truearena.engine.RuleViolation;

import java.util.*;

/** Hub uses standard squares 1–50 and lists captured squares, rather than intermediate landings. */
public final class ScanMoveCodec {
    public record Move(int from, int to) {}

    public static String position(Piece[] board, String side) {
        if (board.length != Board.SIZE || !("A".equals(side) || "B".equals(side)))
            throw new IllegalArgumentException("Invalid draughts position");
        StringBuilder out = new StringBuilder(side.equals("A") ? "B" : "W");
        for (Piece piece : board) out.append(piece == null ? 'e' : switch (piece) {
            case A_MAN -> 'b'; case A_KING -> 'B'; case B_MAN -> 'w'; case B_KING -> 'W';
        });
        return out.toString();
    }

    /** Validate the complete result through the canonical reducer, resolving ambiguous flying-king paths. */
    public static Optional<List<Move>> resolve(Piece[] board, String side, String notation) {
        if (notation == null || !notation.matches("(?:[1-9]|[1-4][0-9]|50)(?:-(?:[1-9]|[1-4][0-9]|50)|(?:x(?:[1-9]|[1-4][0-9]|50)){2,21})"))
            return Optional.empty();
        String[] parts = notation.split("[-x]");
        int from = Integer.parseInt(parts[0]) - 1, target = Integer.parseInt(parts[1]) - 1;
        Set<Integer> captured = new HashSet<>();
        for (int i = 2; i < parts.length; i++) if (!captured.add(Integer.parseInt(parts[i]) - 1)) return Optional.empty();
        if (captured.contains(from) || captured.contains(target)) return Optional.empty();
        var d = new DraughtsState.Draft();
        d.board = board.clone(); d.phase = "Turn" + side; d.playerA = "A"; d.playerB = "B"; d.round = 1;
        d.config = new DraughtsConfig(60, true);
        d.requiredCaptureCount = CaptureEngine.requiredCaptureCount(board, side);
        if ((captured.isEmpty() && d.requiredCaptureCount != 0) || (!captured.isEmpty() && captured.size() != d.requiredCaptureCount))
            return Optional.empty();
        var resolver = new Resolver(side, target, captured);
        return resolver.visit(d.build(), from, new ArrayList<>(), new HashSet<>());
    }

    private static final class Resolver {
        private final String side;
        private final int target;
        private final Set<Integer> captured;
        private final DraughtsModule game = new DraughtsModule();
        private final long deadline = System.nanoTime() + 50_000_000;
        private int nodes;

        Resolver(String side, int target, Set<Integer> captured) { this.side = side; this.target = target; this.captured = captured; }

        Optional<List<Move>> visit(DraughtsState state, int from, List<Move> path, Set<Integer> taken) {
            if (++nodes > 4000 || System.nanoTime() >= deadline || Thread.currentThread().isInterrupted()) return Optional.empty();
            List<CaptureEngine.Landing> landings = captured.isEmpty() ? List.of()
                    : CaptureEngine.captureLandings(state.board, from, state.capturedSquares);
            List<Integer> destinations = captured.isEmpty() ? List.of(target)
                    : landings.stream().filter(l -> captured.contains(l.captured()) && !taken.contains(l.captured()))
                            .map(CaptureEngine.Landing::to).toList();
            for (int to : destinations) {
                Set<Integer> nextTaken = new HashSet<>(taken);
                landings.stream().filter(l -> l.to() == to).findFirst().ifPresent(l -> nextTaken.add(l.captured()));
                if (nextTaken.equals(captured) && to != target) continue;
                try {
                    DraughtsState after = (DraughtsState) game.onPlayerAction(state,
                            PlayerAction.of(side, "MOVE", Map.of("from", from, "to", to)));
                    var nextPath = new ArrayList<>(path); nextPath.add(new Move(from, to));
                    if (after.activeSquare == null) {
                        if (to == target && nextTaken.equals(captured)) return Optional.of(List.copyOf(nextPath));
                    } else {
                        var result = visit(after, to, nextPath, nextTaken);
                        if (result.isPresent()) return result;
                    }
                } catch (RuleViolation ignored) { /* Try another pivot; never loosen server legality. */ }
            }
            return Optional.empty();
        }
    }
    private ScanMoveCodec() {}
}
