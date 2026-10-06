package app.truearena.game.chess;

import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Board rules, one edge case per test, on hand-built positions. */
class PositionRulesTest {

    private static Position fen(String fen) {
        return Position.fromFen(fen);
    }

    private static Set<String> uci(Position p) {
        return p.legalMoves().stream().map(Move::uci).collect(Collectors.toSet());
    }

    private static Set<String> destinations(Position p, String from) {
        return p.legalMovesFrom(Square.parse(from)).stream()
                .map(m -> Square.name(m.to()))
                .collect(Collectors.toSet());
    }

    private static Move find(Position p, String uci) {
        return p.legalMoves().stream().filter(m -> m.uci().equals(uci)).findFirst()
                .orElseThrow(() -> new AssertionError(uci + " is not legal in " + p.fen()));
    }

    @Nested
    class Castling {

        @Test
        void bothSidesAvailableWhenNothingInTheWay() {
            Position p = fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
            assertThat(uci(p)).contains("e1g1", "e1c1");
        }

        @Test
        void cannotCastleThroughAnAttackedSquare() {
            // Rook on f8 covers f1, the square the king crosses going kingside.
            Position p = fen("r3kr2/8/8/8/8/8/8/R3K2R w KQq - 0 1");
            assertThat(uci(p)).doesNotContain("e1g1").contains("e1c1");
        }

        @Test
        void cannotCastleIntoCheck() {
            Position p = fen("r3k1r1/8/8/8/8/8/8/R3K2R w KQq - 0 1");
            assertThat(uci(p)).doesNotContain("e1g1");
        }

        @Test
        void queensideCannotCrossAnAttackedD1() {
            Position p = fen("r2rk3/8/8/8/8/8/8/R3K2R w KQ - 0 1");
            assertThat(uci(p)).doesNotContain("e1c1").contains("e1g1");
        }

        @Test
        void queensideIsFineWhenOnlyB1IsAttacked() {
            // The king never touches b1 — only the rook passes it.
            Position p = fen("1r2k3/8/8/8/8/8/8/R3K2R w KQ - 0 1");
            assertThat(uci(p)).contains("e1c1");
        }

        @Test
        void cannotCastleOutOfCheck() {
            Position p = fen("4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1");
            assertThat(p.inCheck()).isTrue();
            assertThat(uci(p)).doesNotContain("e1g1", "e1c1");
        }

        @Test
        void cannotCastleThroughAPiece() {
            Position p = fen("r3k2r/8/8/8/8/8/8/RN2K1NR w KQkq - 0 1");
            assertThat(uci(p)).doesNotContain("e1g1", "e1c1");
        }

        @Test
        void castlingMovesTheRookToo() {
            Position after = fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1").play(find(
                    fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"), "e1c1"));
            assertThat(after.at(Square.parse("c1"))).isEqualTo(Piece.WHITE_KING);
            assertThat(after.at(Square.parse("d1"))).isEqualTo(Piece.WHITE_ROOK);
            assertThat(after.at(Square.parse("a1"))).isNull();
            assertThat(after.castlingRights() & (Position.WHITE_KINGSIDE | Position.WHITE_QUEENSIDE)).isZero();
        }

        @Test
        void aKingThatMovedAndCameBackHasLostTheRight() {
            Position p = fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
            p = p.play(find(p, "e1f1"));
            p = p.play(find(p, "e8f8"));
            p = p.play(find(p, "f1e1"));
            p = p.play(find(p, "f8e8"));
            assertThat(uci(p)).doesNotContain("e1g1", "e1c1");
        }

        @Test
        void aRookThatMovedLosesOnlyItsOwnSide() {
            Position p = fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
            p = p.play(find(p, "h1h2"));
            p = p.play(find(p, "a8a7"));
            assertThat(p.castlingRights()).isEqualTo(Position.WHITE_QUEENSIDE | Position.BLACK_KINGSIDE);
        }

        @Test
        void capturingARookOnItsCornerRemovesThatRight() {
            Position p = fen("r3k2r/8/8/8/8/8/6b1/R3K2R b KQkq - 0 1");
            p = p.play(find(p, "g2h1"));
            assertThat(p.castlingRights() & Position.WHITE_KINGSIDE).isZero();
            assertThat(uci(p)).doesNotContain("e1g1");
        }

        @Test
        void fenRightsWithoutTheRookAreDropped() {
            assertThat(fen("4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1").castlingRights()).isZero();
        }
    }

    @Nested
    class Pins {

        @Test
        void anAbsolutelyPinnedKnightCannotMove() {
            Position p = fen("4k3/4r3/8/8/8/8/4N3/4K3 w - - 0 1");
            assertThat(destinations(p, "e2")).isEmpty();
        }

        @Test
        void aPinnedRookMayOnlySlideAlongThePin() {
            Position p = fen("4k3/4r3/8/8/8/8/4R3/4K3 w - - 0 1");
            assertThat(destinations(p, "e2")).containsExactlyInAnyOrder("e3", "e4", "e5", "e6", "e7");
        }

        @Test
        void aPinnedBishopMayCaptureItsPinner() {
            Position p = fen("7k/8/8/8/3q4/8/1B6/K7 w - - 0 1");
            assertThat(destinations(p, "b2")).containsExactlyInAnyOrder("c3", "d4");
        }

        @Test
        void aPinnedPawnCannotCaptureOffTheLine() {
            // Pinned along the e-file: it may push, but not take on d3.
            Position p = fen("4k3/4r3/8/8/8/3p4/4P3/4K3 w - - 0 1");
            assertThat(destinations(p, "e2")).containsExactlyInAnyOrder("e3", "e4");
        }

        @Test
        void theKingCannotStepAlongTheLineOfTheCheck() {
            // Retreating away from a rook along its own line is still in check.
            Position p = fen("4k3/8/8/8/4r3/8/8/4K3 w - - 0 1");
            assertThat(destinations(p, "e1")).doesNotContain("e2").contains("d1", "f1", "d2", "f2");
        }
    }

    @Nested
    class EnPassant {

        @Test
        void availableImmediatelyAfterTheDoublePush() {
            Position p = fen("4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1");
            p = p.play(find(p, "d7d5"));
            assertThat(p.epSquare()).isEqualTo(Square.parse("d6"));
            Move ep = find(p, "e5d6");
            assertThat(ep.flag()).isEqualTo(Move.Flag.EN_PASSANT);
            Position after = p.play(ep);
            assertThat(after.at(Square.parse("d5"))).as("the captured pawn is removed").isNull();
            assertThat(after.at(Square.parse("d6"))).isEqualTo(Piece.WHITE_PAWN);
        }

        @Test
        void lostIfNotTakenAtOnce() {
            Position p = fen("4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1");
            p = p.play(find(p, "d7d5"));
            p = p.play(find(p, "e1f1"));
            p = p.play(find(p, "e8f8"));
            assertThat(uci(p)).doesNotContain("e5d6");
        }

        @Test
        void notAllowedWhenItWouldExposeTheKingAlongTheRank() {
            // Both pawns leave the fifth rank, opening a5–h5 to the rook.
            Position p = fen("8/8/8/K1pP3r/8/8/8/7k w - c6 0 1");
            assertThat(uci(p)).doesNotContain("d5c6").contains("d5d6");
        }

        @Test
        void notAllowedWhenTheCapturingPawnIsPinnedOffTheLine() {
            // e5 is pinned to e1 along the file; capturing onto d6 leaves it.
            Position p = fen("4r1k1/8/8/3pP3/8/8/8/4K3 w - d6 0 1");
            assertThat(uci(p)).doesNotContain("e5d6").contains("e5e6");
        }

        @Test
        void allowedWhenTheCaptureStaysOnThePinLine() {
            // e5 is pinned to h2 along the c7–h2 diagonal, and d6 lies on it.
            Position p = fen("4k3/2b5/8/3pP3/8/8/7K/8 w - d6 0 1");
            assertThat(uci(p)).contains("e5d6").doesNotContain("e5e6");
        }

        @Test
        void canBeTheMoveThatRemovesACheckingPawn() {
            Position p = fen("8/2p5/8/3P4/3K4/8/8/7k b - - 0 1");
            p = p.play(find(p, "c7c5"));
            assertThat(p.inCheck()).as("c5 gives check to d4").isTrue();
            assertThat(uci(p)).contains("d5c6");
            assertThat(p.play(find(p, "d5c6")).at(Square.parse("c5"))).isNull();
        }

        @Test
        void repetitionIgnoresAnEnPassantSquareThatCantBeUsed() {
            Position withUselessEp = fen("8/8/8/K1pP3r/8/8/8/7k w - c6 0 1");
            Position withoutEp = fen("8/8/8/K1pP3r/8/8/8/7k w - - 0 1");
            assertThat(withUselessEp.repetitionKey()).isEqualTo(withoutEp.repetitionKey());
        }

        @Test
        void repetitionCountsAUsableEnPassantSquare() {
            Position withEp = fen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1");
            Position withoutEp = fen("4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1");
            assertThat(withEp.repetitionKey()).isNotEqualTo(withoutEp.repetitionKey());
        }
    }

    @Nested
    class Promotion {

        @Test
        void eachOfTheFourPiecesIsASeparateMove() {
            Position p = fen("8/P7/8/8/8/8/8/k6K w - - 0 1");
            assertThat(uci(p)).contains("a7a8q", "a7a8r", "a7a8b", "a7a8n").doesNotContain("a7a8");
        }

        @Test
        void promotesOnCaptureToo() {
            Position p = fen("1r6/P7/8/8/8/8/8/k6K w - - 0 1");
            Position after = p.play(find(p, "a7b8n"));
            assertThat(after.at(Square.parse("b8"))).isEqualTo(Piece.WHITE_KNIGHT);
            assertThat(after.at(Square.parse("a7"))).isNull();
        }

        @Test
        void blackPromotesOnTheFirstRank() {
            Position p = fen("K6k/8/8/8/8/8/p7/8 b - - 0 1");
            assertThat(p.play(find(p, "a2a1r")).at(Square.parse("a1"))).isEqualTo(Piece.BLACK_ROOK);
        }

        @Test
        void underpromotionToAKnightCanGiveCheck() {
            Position p = fen("8/4P1k1/8/8/8/8/8/K7 w - - 0 1");
            assertThat(p.play(find(p, "e7e8n")).inCheck()).isTrue();
        }
    }

    @Nested
    class Endings {

        @Test
        void checkmateMeansInCheckWithNoMoves() {
            Position p = fen("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3");
            assertThat(p.inCheck()).isTrue();
            assertThat(p.legalMoves()).isEmpty();
        }

        @Test
        void stalemateMeansNoMovesWithoutCheck() {
            Position p = fen("k7/2Q5/8/8/8/8/8/7K b - - 0 1");
            assertThat(p.inCheck()).isFalse();
            assertThat(p.legalMoves()).isEmpty();
        }

        @Test
        void deadPositions() {
            assertThat(fen("4k3/8/8/8/8/8/8/4K3 w - - 0 1").isDeadPosition()).as("K v K").isTrue();
            assertThat(fen("4k3/8/8/8/8/8/8/2B1K3 w - - 0 1").isDeadPosition()).as("KB v K").isTrue();
            assertThat(fen("4k3/8/8/8/8/8/8/1N2K3 w - - 0 1").isDeadPosition()).as("KN v K").isTrue();
            assertThat(fen("2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1").isDeadPosition())
                    .as("bishops on opposite-coloured squares can still help mate").isFalse();
            assertThat(fen("1b2k3/8/8/8/8/8/8/2B1K3 w - - 0 1").isDeadPosition())
                    .as("KB v KB, both bishops on dark squares").isTrue();
            assertThat(fen("4k3/8/8/8/8/8/8/1NN1K3 w - - 0 1").isDeadPosition())
                    .as("two knights can't force mate, but mate is possible").isFalse();
            assertThat(fen("1n2k3/8/8/8/8/8/8/1N2K3 w - - 0 1").isDeadPosition()).as("KN v KN").isFalse();
            assertThat(fen("4k3/8/8/8/8/8/P7/4K3 w - - 0 1").isDeadPosition()).as("a pawn can promote").isFalse();
        }

        @Test
        void whoCanStillCheckmate() {
            Position knightVsQueen = fen("4k3/8/8/8/8/8/3q4/1N2K3 w - - 0 1");
            assertThat(knightVsQueen.canEverCheckmate(Color.WHITE))
                    .as("a lone knight can mate if the opponent's own pieces box their king in").isTrue();
            Position bareKing = fen("4k3/8/8/8/8/8/3q4/4K3 w - - 0 1");
            assertThat(bareKing.canEverCheckmate(Color.WHITE)).isFalse();
            assertThat(bareKing.canEverCheckmate(Color.BLACK)).isTrue();
        }
    }

    @Nested
    class Notation {

        private String san(String fen, String uci) {
            Position p = fen(fen);
            return San.of(p, find(p, uci));
        }

        @Test
        void pawnPiecesCapturesAndCastling() {
            assertThat(san(Position.START_FEN, "e2e4")).isEqualTo("e4");
            assertThat(san(Position.START_FEN, "g1f3")).isEqualTo("Nf3");
            assertThat(san("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1", "e4d5")).isEqualTo("exd5");
            assertThat(san("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1g1")).isEqualTo("O-O");
            assertThat(san("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1c1")).isEqualTo("O-O-O");
            assertThat(san("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "e5d6")).isEqualTo("exd6");
        }

        @Test
        void promotionCheckAndMate() {
            assertThat(san("8/P7/8/8/8/8/8/k6K w - - 0 1", "a7a8q")).isEqualTo("a8=Q+");
            assertThat(san("8/P7/8/8/8/8/8/k6K w - - 0 1", "a7a8n")).isEqualTo("a8=N");
            assertThat(san("rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2", "d8h4")).isEqualTo("Qh4#");
        }

        @Test
        void disambiguatesByFileThenRankThenBoth() {
            assertThat(san("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1", "b1d2")).isEqualTo("Nbd2");
            assertThat(san("4k3/R7/8/8/8/8/8/R3K3 w - - 0 1", "a1a4")).isEqualTo("R1a4");
            assertThat(san("7k/8/8/8/2Q1Q3/8/2Q5/4K3 w - - 0 1", "c4d3")).isEqualTo("Qc4d3");
        }

        @Test
        void aPinnedTwinDoesNotNeedDistinguishing() {
            // Both knights could reach e4, but the h4 bishop pins g3 to e1.
            assertThat(san("6k1/8/8/8/8/2N3N1/8/4K3 w - - 0 1", "c3e4")).isEqualTo("Nce4");
            assertThat(san("6k1/8/8/8/7b/2N3N1/8/4K3 w - - 0 1", "c3e4")).isEqualTo("Ne4");
        }
    }

    @Nested
    class Fen {

        @Test
        void roundTrips() {
            for (String fen : List.of(Position.START_FEN,
                    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
                    "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
                    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 b - - 13 40")) {
                assertThat(fen(fen).fen()).isEqualTo(fen);
            }
        }

        @Test
        void countersAdvanceCorrectly() {
            Position p = Position.initial();
            p = p.play(find(p, "g1f3"));
            assertThat(p.halfmoveClock()).isEqualTo(1);
            assertThat(p.fullmoveNumber()).isEqualTo(1);
            p = p.play(find(p, "e7e5"));
            assertThat(p.halfmoveClock()).as("pawn move resets").isZero();
            assertThat(p.fullmoveNumber()).isEqualTo(2);
        }

        @Test
        void rejectsImpossiblePositions() {
            assertThatThrownBy(() -> fen("8/8/8/8/8/8/8/4K3 w - - 0 1")).isInstanceOf(IllegalArgumentException.class);
            assertThatThrownBy(() -> fen("4k3/8/8/8/8/8/8/4K2r b - - 0 1"))
                    .as("the side not to move can't be in check").isInstanceOf(IllegalArgumentException.class);
        }
    }
}
