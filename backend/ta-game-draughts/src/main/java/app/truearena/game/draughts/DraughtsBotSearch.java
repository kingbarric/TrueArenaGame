package app.truearena.game.draughts;

import app.truearena.engine.GameState;
import app.truearena.engine.GameTreeSearch;
import app.truearena.engine.PlayerAction;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Collection;

/** Search reconstructs only the public board and uses the authoritative reducer for every branch. */
public final class DraughtsBotSearch {
    public static Optional<PlayerAction> choose(Piece[] board, String a, String b, String player,
            Integer activeSquare, boolean mandatory, int depth, long millis) {
        return choose(board, a, b, player, activeSquare, 0L, mandatory, depth, millis);
    }

    public static Optional<PlayerAction> choose(Piece[] board, String a, String b, String player,
            Integer activeSquare, long capturedSquares, boolean mandatory, int depth, long millis) {
        return choose(board, a, b, player, activeSquare, capturedSquares, mandatory, false, List.of(), depth, millis);
    }

    public static Optional<PlayerAction> choose(Piece[] board, String a, String b, String player,
            Integer activeSquare, long capturedSquares, boolean mandatory, boolean seizure,
            Collection<Integer> seizable, int depth, long millis) {
        if (!player.equals(a) && !player.equals(b)) return Optional.empty();
        DraughtsState.Draft d = new DraughtsState.Draft();
        d.playerA = a; d.playerB = b; d.board = board.clone();
        String side = player.equals(a) ? "A" : "B";
        d.phase = "Turn" + side; d.round = 1;
        d.config = new DraughtsConfig(60, mandatory, seizure);
        d.seizable.addAll(seizable);
        d.activeSquare = activeSquare;
        d.capturedSquares = capturedSquares;
        d.requiredCaptureCount = !mandatory ? 0 : activeSquare == null
                ? CaptureEngine.requiredCaptureCount(board, side) : CaptureEngine.maxCaptureCount(board, activeSquare, capturedSquares);
        DraughtsModule game = new DraughtsModule();
        return GameTreeSearch.choose(game, d.build(), player, state -> legal(game, state),
                state -> evaluate((DraughtsState) state, side), depth, millis);
    }

    @SuppressWarnings("unchecked")
    private static List<PlayerAction> legal(DraughtsModule game, GameState state) {
        if (state.finished()) return List.of();
        String actor = game.playersToAct(state).iterator().next();
        Map<String, Object> view = game.visibleStateFor(state, actor).data();
        Map<String, List<Integer>> moves = (Map<String, List<Integer>>) view.get("legalMoves");
        List<PlayerAction> out = new ArrayList<>();
        for (int square : (List<Integer>) view.get("seizable")) {
            out.add(PlayerAction.of(actor, "SEIZE", Map.of("square", square)));
        }
        moves.forEach((from, destinations) -> destinations.forEach(to -> out.add(
                PlayerAction.of(actor, "MOVE", Map.of("from", Integer.parseInt(from), "to", to)))));
        return out;
    }

    private static double evaluate(DraughtsState state, String side) {
        if (state.finished()) return state.win.winningSide().equals(side) ? 100000 : -100000;
        double score = 0;
        for (int sq = 0; sq < Board.SIZE; sq++) {
            Piece piece = state.board[sq];
            if (piece == null) continue;
            int advance = piece.side().equals("A") ? Board.rowOf(sq) : 9 - Board.rowOf(sq);
            double value = piece.isKing() ? 330 : 100 + advance * 4;
            value += 4 - Math.abs(4.5 - Board.colOf(sq));
            value += CaptureEngine.simpleLandings(state.board, sq).size();
            score += piece.side().equals(side) ? value : -value;
        }
        return score;
    }

    private DraughtsBotSearch() {}
}
