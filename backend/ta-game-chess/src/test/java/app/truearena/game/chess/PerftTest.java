package app.truearena.game.chess;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Perft: count every leaf of the legal-move tree to a fixed depth and compare
 * with the published reference counts (chessprogramming.org/Perft_Results).
 * Any bug in castling, en passant, promotion, pins or check evasion shows up
 * as a wrong count — these positions were built to exercise exactly those.
 */
class PerftTest {

    @ParameterizedTest(name = "{0} depth {2} = {3}")
    @CsvSource(delimiter = '|', value = {
            "start      | rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1             | 1 | 20",
            "start      | rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1             | 2 | 400",
            "start      | rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1             | 3 | 8902",
            "start      | rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1             | 4 | 197281",
            "kiwipete   | r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1 | 1 | 48",
            "kiwipete   | r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1 | 2 | 2039",
            "kiwipete   | r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1 | 3 | 97862",
            "position3  | 8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1                             | 4 | 43238",
            "position3  | 8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1                             | 5 | 674624",
            "position4  | r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1     | 3 | 9467",
            "position4m | r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1     | 3 | 9467",
            "position5  | rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8            | 3 | 62379",
            "position6  | r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10 | 3 | 89890",
    })
    void moveGenerationMatchesReferenceCounts(String name, String fen, int depth, long expected) {
        assertThat(perft(Position.fromFen(fen), depth)).isEqualTo(expected);
    }

    private static long perft(Position position, int depth) {
        var moves = position.legalMoves();
        if (depth == 1) {
            return moves.size();
        }
        long nodes = 0;
        for (Move m : moves) {
            nodes += perft(position.play(m), depth - 1);
        }
        return nodes;
    }
}
