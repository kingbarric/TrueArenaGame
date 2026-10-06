package app.truearena.game.chess;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

import java.util.HashSet;
import java.util.Random;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class ChessEngineTest {

    /** A Random that never rolls the Amateur's "play anything" chance, so tactics tests are deterministic. */
    private static Random steady() {
        return new Random(7) {
            @Override
            public double nextDouble() {
                return 0.99;
            }
        };
    }

    private static Move best(String fen, ChessEngine.Level level) {
        return new ChessEngine(steady()).choose(Position.fromFen(fen), Set.of(), level, 2000).orElseThrow().move();
    }

    @ParameterizedTest
    @EnumSource(ChessEngine.Level.class)
    void everyLevelFindsMateInOne(ChessEngine.Level level) {
        // Back-rank mate: Ra8#.
        Move m = best("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", level);
        assertThat(m.uci()).isEqualTo("a1a8");
    }

    @ParameterizedTest
    @EnumSource(value = ChessEngine.Level.class, names = {"PRO", "LEGEND"})
    void takesAHangingQueen(ChessEngine.Level level) {
        Move m = best("4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1", level);
        assertThat(m.uci()).isEqualTo("d2d5");
    }

    @ParameterizedTest
    @EnumSource(value = ChessEngine.Level.class, names = {"PRO", "LEGEND"})
    void doesNotTakeAPoisonedPawn(ChessEngine.Level level) {
        // Qxb7?? loses the queen to the rook on b8.
        Move m = best("1r2k3/1p6/8/8/8/8/8/1Q2K3 w - - 0 1", level);
        assertThat(m.uci()).isNotEqualTo("b1b7");
    }

    @Test
    void legendTakesTheRookWithMate() {
        // Rxd8 wins the rook and mates on the back rank in one go.
        Move m = best("3r2k1/5ppp/8/8/8/8/5PPP/3RR1K1 w - - 0 1", ChessEngine.Level.LEGEND);
        assertThat(m.uci()).isEqualTo("d1d8");
    }

    @Test
    void noMoveWhenTheGameIsOver() {
        Position mated = Position.fromFen("R5k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1");
        assertThat(new ChessEngine(steady()).choose(mated, Set.of(), ChessEngine.Level.LEGEND, 500)).isEmpty();
    }

    @Test
    void respectsItsThinkingBudget() {
        long start = System.currentTimeMillis();
        new ChessEngine(steady()).choose(Position.initial(), Set.of(), ChessEngine.Level.LEGEND, 300);
        assertThat(System.currentTimeMillis() - start).isLessThan(1500);
    }

    @Test
    void selfPlayOnlyEverMakesLegalMovesAndFinishes() {
        Random rng = new Random(11);
        ChessEngine white = new ChessEngine(rng);
        ChessEngine black = new ChessEngine(rng);
        Position p = Position.initial();
        Set<String> seen = new HashSet<>();
        for (int ply = 0; ply < 60; ply++) {
            ChessEngine side = p.sideToMove() == Color.WHITE ? white : black;
            var r = side.choose(p, seen, ChessEngine.Level.AMATEUR, 100);
            if (r.isEmpty()) {
                break;
            }
            assertThat(p.legalMoves()).contains(r.get().move());
            seen.add(p.repetitionKey());
            p = p.play(r.get().move());
        }
    }

    @Test
    void evaluationIsSymmetric() {
        assertThat(ChessEngine.evaluate(Position.initial())).isZero();
        int white = ChessEngine.evaluate(Position.fromFen("4k3/8/8/8/8/8/8/3QK3 w - - 0 1"));
        int black = ChessEngine.evaluate(Position.fromFen("3qk3/8/8/8/8/8/8/4K3 b - - 0 1"));
        assertThat(white).isEqualTo(black).isGreaterThan(800);
    }
}
