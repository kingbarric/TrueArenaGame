package app.truearena.api.bot;

import app.truearena.game.draughts.Piece;
import app.truearena.game.draughts.ScanMoveCodec;
import java.util.List;
import java.util.Optional;

@FunctionalInterface
public interface DraughtsMoveSource {
    Optional<List<ScanMoveCodec.Move>> choose(Piece[] board, String side, Difficulty difficulty, long budgetMs);
}
