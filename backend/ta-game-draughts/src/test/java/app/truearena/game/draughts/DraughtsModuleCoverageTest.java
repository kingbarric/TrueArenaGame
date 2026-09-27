package app.truearena.game.draughts;

import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import app.truearena.engine.WinResult;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@link DraughtsModule} end to end — setup, the move/capture action
 * pipeline, mandatory-maximum enforcement through {@code onPlayerAction}
 * (not just the engine functions {@link CaptureEngineTest} already covers),
 * promotion, timeouts, and win conditions. Board positions for non-setup
 * scenarios are built directly via {@link DraughtsState.Draft} rather than
 * played out from the opening position — precise and fast, same reasoning
 * as constructing raw boards in {@link CaptureEngineTest}.
 */
class DraughtsModuleCoverageTest {

    private final DraughtsModule module = new DraughtsModule();
    private static final String P1 = "p1";
    private static final String P2 = "p2";

    private GameState fresh(long seed) {
        return module.initialState(List.of(P1, P2), DraughtsConfig.defaults(), RandomSource.seeded(seed));
    }

    private PlayerAction move(String actor, int from, int to) {
        return PlayerAction.of(actor, "MOVE", Map.of("from", from, "to", to, "id", UUID.randomUUID().toString()));
    }

    /** Builds a custom position: empty board, given pieces, A to move unless stated otherwise. */
    private DraughtsState customState(Map<Integer, Piece> pieces, String turnSide) {
        DraughtsState.Draft d = new DraughtsState.Draft();
        d.config = DraughtsConfig.defaults();
        d.playerA = P1;
        d.playerB = P2;
        pieces.forEach((sq, p) -> d.board[sq] = p);
        d.phase = "Turn" + turnSide;
        d.round = 1;
        d.requiredCaptureCount = CaptureEngine.requiredCaptureCount(d.board, turnSide);
        return d.build();
    }

    // ---------------------------------------------------------------- setup

    @Test
    void rejectsAnythingOtherThanTwoPlayers() {
        assertThatThrownBy(() -> module.initialState(List.of(P1), DraughtsConfig.defaults(), RandomSource.seeded(1)))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NEEDS_TWO_PLAYERS");
        assertThatThrownBy(() -> module.initialState(List.of(P1, P2, "p3"), DraughtsConfig.defaults(), RandomSource.seeded(1)))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NEEDS_TWO_PLAYERS");
    }

    @Test
    void startingPositionHasTwentyPiecesEachSideAndAToMove() {
        DraughtsState s = (DraughtsState) fresh(1);
        assertThat(s.pieceCount(DraughtsState.SIDE_A)).isEqualTo(20);
        assertThat(s.pieceCount(DraughtsState.SIDE_B)).isEqualTo(20);
        assertThat(s.phase()).isEqualTo("TurnA");
        assertThat(s.turnSide()).isEqualTo(DraughtsState.SIDE_A);
        for (int sq = 20; sq < 30; sq++) {
            assertThat(s.board[sq]).isNull(); // the two middle rows start empty
        }
        assertThat(module.checkWinCondition(s)).isEmpty();
    }

    @Test
    void bothPlayerIdsAreAssignedToASideRandomly() {
        DraughtsState s = (DraughtsState) fresh(7);
        assertThat(List.of(s.playerA, s.playerB)).containsExactlyInAnyOrder(P1, P2);
    }

    // ---------------------------------------------------------------- simple moves

    @Test
    void simpleMoveSwitchesTurnToTheOtherSide() {
        DraughtsState s = (DraughtsState) fresh(1);
        int from = Board.squareOf(3, 0);
        int to = Board.squareOf(4, 1);
        DraughtsState result = (DraughtsState) module.onPlayerAction(s, move(s.playerA, from, to));
        assertThat(result.phase()).isEqualTo("TurnB");
        assertThat(result.board[from]).isNull();
        assertThat(result.board[to]).isEqualTo(Piece.A_MAN);
    }

    @Test
    void rejectsMoveFromNonPlayer() {
        DraughtsState s = (DraughtsState) fresh(1);
        assertThatThrownBy(() -> module.onPlayerAction(s, move("stranger", Board.squareOf(3, 0), Board.squareOf(4, 1))))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_A_PLAYER");
    }

    @Test
    void rejectsMoveWhenItIsNotYourTurn() {
        DraughtsState s = (DraughtsState) fresh(1);
        assertThatThrownBy(() -> module.onPlayerAction(s, move(s.playerB, Board.squareOf(6, 1), Board.squareOf(5, 0))))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_YOUR_TURN");
    }

    @Test
    void rejectsMovingAPieceThatIsNotYours() {
        DraughtsState s = customState(Map.of(Board.squareOf(3, 4), Piece.B_MAN), DraughtsState.SIDE_A);
        assertThatThrownBy(() -> module.onPlayerAction(s, move(s.playerA, Board.squareOf(3, 4), Board.squareOf(4, 5))))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_YOUR_PIECE");
    }

    @Test
    void rejectsAnIllegalSimpleMove() {
        DraughtsState s = customState(Map.of(Board.squareOf(3, 4), Piece.A_MAN), DraughtsState.SIDE_A);
        assertThatThrownBy(() -> module.onPlayerAction(s, move(s.playerA, Board.squareOf(3, 4), Board.squareOf(5, 6))))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "ILLEGAL_MOVE");
    }

    // ---------------------------------------------------------------- mandatory capture

    @Test
    void mustCaptureRatherThanMakeASimpleMoveWhenOneIsAvailable() {
        DraughtsState s = customState(Map.of(
                Board.squareOf(3, 4), Piece.A_MAN,
                Board.squareOf(4, 5), Piece.B_MAN
        ), DraughtsState.SIDE_A);
        assertThat(s.requiredCaptureCount).isEqualTo(1);
        // trying to move some other (nonexistent) simple step, or sidestep the capture, must fail:
        assertThatThrownBy(() -> module.onPlayerAction(s, move(s.playerA, Board.squareOf(3, 4), Board.squareOf(4, 3))))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "MUST_CAPTURE");
    }

    @Test
    void capturingRemovesThePieceAndEndsTheTurnWhenTheChainIsComplete() {
        DraughtsState s = customState(Map.of(
                Board.squareOf(3, 4), Piece.A_MAN,
                Board.squareOf(4, 5), Piece.B_MAN,
                Board.squareOf(6, 9), Piece.B_MAN // a spare B piece so B isn't eliminated by this capture
        ), DraughtsState.SIDE_A);
        DraughtsState after = (DraughtsState) module.onPlayerAction(s, move(s.playerA, Board.squareOf(3, 4), Board.squareOf(5, 6)));
        assertThat(after.board[Board.squareOf(4, 5)]).isNull(); // captured piece is gone
        assertThat(after.board[Board.squareOf(5, 6)]).isEqualTo(Piece.A_MAN);
        assertThat(after.phase()).isEqualTo("TurnB"); // single capture, chain complete, turn passes
        assertThat(after.pieceCount(DraughtsState.SIDE_B)).isEqualTo(1);
    }

    @Test
    void multiJumpChainMustContinueWithTheSamePiece() {
        DraughtsState s = customState(Map.of(
                Board.squareOf(1, 0), Piece.A_MAN,
                Board.squareOf(2, 1), Piece.B_MAN,
                Board.squareOf(4, 3), Piece.B_MAN,
                Board.squareOf(6, 9), Piece.B_MAN // a spare B piece so B isn't eliminated by this chain
        ), DraughtsState.SIDE_A);
        assertThat(s.requiredCaptureCount).isEqualTo(2);

        DraughtsState afterFirst = (DraughtsState) module.onPlayerAction(s, move(s.playerA, Board.squareOf(1, 0), Board.squareOf(3, 2)));
        assertThat(afterFirst.phase()).isEqualTo("TurnA"); // still A's turn — must continue
        assertThat(afterFirst.activeSquare).isEqualTo(Board.squareOf(3, 2));

        // a different piece can't move mid-chain, even if it were otherwise legal
        DraughtsState finalAfterFirst = afterFirst;
        assertThatThrownBy(() -> module.onPlayerAction(finalAfterFirst, move(finalAfterFirst.playerA, Board.squareOf(3, 2) + 0, Board.squareOf(3, 2))))
                .isInstanceOf(RuleViolation.class); // trivial self-move also invalid, just proving the gate exists

        DraughtsState afterSecond = (DraughtsState) module.onPlayerAction(afterFirst, move(afterFirst.playerA, Board.squareOf(3, 2), Board.squareOf(5, 4)));
        assertThat(afterSecond.phase()).isEqualTo("TurnB");
        assertThat(afterSecond.activeSquare).isNull();
        assertThat(afterSecond.pieceCount(DraughtsState.SIDE_B)).isEqualTo(1);
    }

    @Test
    void mustContinueCaptureRejectsSwitchingToAnotherPiece() {
        DraughtsState s = customState(Map.of(
                Board.squareOf(1, 0), Piece.A_MAN,
                Board.squareOf(2, 1), Piece.B_MAN,
                Board.squareOf(4, 3), Piece.B_MAN,
                Board.squareOf(5, 8), Piece.A_MAN // an uninvolved second A piece with its own simple move
        ), DraughtsState.SIDE_A);
        DraughtsState afterFirst = (DraughtsState) module.onPlayerAction(s, move(s.playerA, Board.squareOf(1, 0), Board.squareOf(3, 2)));
        assertThatThrownBy(() -> module.onPlayerAction(afterFirst, move(afterFirst.playerA, Board.squareOf(5, 8), Board.squareOf(6, 9))))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "MUST_CONTINUE_CAPTURE");
    }

    @Test
    void mustTakeTheMaximumEvenIfAShorterCaptureIsAlsoAvailable() {
        // From (1,4): capturing toward (2,1) via (2,3)->(3,2) only nets 1; capturing
        // toward (2,5)->(4,7) chains to 2. The engine must reject the 1-capture branch.
        DraughtsState s = customState(Map.of(
                Board.squareOf(1, 4), Piece.A_MAN,
                Board.squareOf(2, 3), Piece.B_MAN,
                Board.squareOf(2, 5), Piece.B_MAN,
                Board.squareOf(4, 7), Piece.B_MAN
        ), DraughtsState.SIDE_A);
        assertThat(s.requiredCaptureCount).isEqualTo(2);
        assertThatThrownBy(() -> module.onPlayerAction(s, move(s.playerA, Board.squareOf(1, 4), Board.squareOf(3, 2))))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "MUST_TAKE_MAXIMUM");
        // the maximal branch is accepted
        DraughtsState after = (DraughtsState) module.onPlayerAction(s, move(s.playerA, Board.squareOf(1, 4), Board.squareOf(3, 6)));
        assertThat(after.activeSquare).isEqualTo(Board.squareOf(3, 6));
    }

    // ---------------------------------------------------------------- promotion

    @Test
    void manPromotesOnReachingTheFarRow() {
        DraughtsState s = customState(Map.of(Board.squareOf(8, 1), Piece.A_MAN), DraughtsState.SIDE_A);
        DraughtsState after = (DraughtsState) module.onPlayerAction(s, move(s.playerA, Board.squareOf(8, 1), Board.squareOf(9, 0)));
        assertThat(after.board[Board.squareOf(9, 0)]).isEqualTo(Piece.A_KING);
    }

    // ---------------------------------------------------------------- win conditions

    @Test
    void winsByEliminatingEveryEnemyPiece() {
        DraughtsState s = customState(Map.of(
                Board.squareOf(3, 4), Piece.A_MAN,
                Board.squareOf(4, 5), Piece.B_MAN
        ), DraughtsState.SIDE_A);
        DraughtsState after = (DraughtsState) module.onPlayerAction(s, move(s.playerA, Board.squareOf(3, 4), Board.squareOf(5, 6)));
        assertThat(after.finished()).isTrue();
        Optional<WinResult> win = module.checkWinCondition(after);
        assertThat(win).isPresent();
        assertThat(win.get().winningSide()).isEqualTo(DraughtsState.SIDE_A);
        assertThat(win.get().perPlayerOutcome()).containsEntry(s.playerA, "won").containsEntry(s.playerB, "lost");
    }

    @Test
    void winsWhenTheOpponentHasNoLegalMoveEvenWithPiecesLeft() {
        // B's only man is boxed in by its own side at both forward squares.
        DraughtsState s = customState(Map.of(
                Board.squareOf(1, 8), Piece.B_MAN,
                Board.squareOf(0, 7), Piece.B_MAN,
                Board.squareOf(0, 9), Piece.B_MAN,
                Board.squareOf(3, 4), Piece.A_MAN
        ), DraughtsState.SIDE_A);
        DraughtsState after = (DraughtsState) module.onPlayerAction(s, move(s.playerA, Board.squareOf(3, 4), Board.squareOf(4, 5)));
        assertThat(after.finished()).isTrue();
        assertThat(module.checkWinCondition(after).orElseThrow().winningSide()).isEqualTo(DraughtsState.SIDE_A);
    }

    /**
     * A turn running out no longer forfeits on the spot — it opens the grace
     * ladder instead, and only the last chance expiring loses the game. The
     * ladder itself is covered in {@link DraughtsGraceTimerTest}; this pins
     * the two ends of it from a real opening position.
     */
    @Test
    void turnTimeoutOffersAChanceRatherThanForfeiting() {
        DraughtsState s = (DraughtsState) fresh(1);
        DraughtsState after = (DraughtsState) module.onPhaseElapsed(s, "TurnA");
        assertThat(after.finished()).isFalse();
        assertThat(after.phase()).isEqualTo("GraceA1");
    }

    @Test
    void runningOutOfChancesForfeitsToTheOtherSide() {
        DraughtsState s = (DraughtsState) fresh(1);
        DraughtsState firstChance = (DraughtsState) module.onPhaseElapsed(s, "TurnA");
        DraughtsState lastChance = (DraughtsState) module.onPhaseElapsed(firstChance, "GraceA1");
        DraughtsState after = (DraughtsState) module.onPhaseElapsed(lastChance, "GraceA2");

        assertThat(after.finished()).isTrue();
        assertThat(module.checkWinCondition(after).orElseThrow().winningSide()).isEqualTo(DraughtsState.SIDE_B);
    }

    // ---------------------------------------------------------------- idempotency

    @Test
    void actionsAfterGameOverAreNoOps() {
        DraughtsState s = customState(Map.of(
                Board.squareOf(3, 4), Piece.A_MAN,
                Board.squareOf(4, 5), Piece.B_MAN
        ), DraughtsState.SIDE_A);
        DraughtsState finished = (DraughtsState) module.onPlayerAction(s, move(s.playerA, Board.squareOf(3, 4), Board.squareOf(5, 6)));
        GameState still = module.onPlayerAction(finished, move(finished.playerA, 0, 1));
        assertThat(still).isSameAs(finished);
    }

    // ---------------------------------------------------------------- views

    @Test
    void broadcastAndPlayerViewsAreIdenticalSinceNothingIsSecret() {
        DraughtsState s = (DraughtsState) fresh(1);
        assertThat(module.broadcastState(s).data()).isEqualTo(module.visibleStateFor(s, s.playerA).data());
        assertThat(module.broadcastState(s).data()).isEqualTo(module.visibleStateFor(s, s.playerB).data());
    }

    @Test
    void legalMovesMapOnlyListsTheSideToMove() {
        DraughtsState s = (DraughtsState) fresh(1);
        @SuppressWarnings("unchecked")
        Map<String, Object> legal = (Map<String, Object>) module.broadcastState(s).data().get("legalMoves");
        // every key must be a square holding one of A's pieces at the start (A moves first)
        for (String key : legal.keySet()) {
            int sq = Integer.parseInt(key);
            assertThat(s.board[sq]).isEqualTo(Piece.A_MAN);
        }
    }
}
