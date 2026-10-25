package app.truearena.api.bot;

import app.truearena.game.chess.Move;
import app.truearena.game.chess.Position;

import java.util.List;
import java.util.Optional;

/** A local chess engine. No network or language-model decisions are involved. */
@FunctionalInterface
public interface ChessMoveSource {
    Optional<Move> choose(Position position, List<String> uciHistory, Difficulty level, long budgetMs);
}
