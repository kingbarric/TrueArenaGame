package app.truearena.game.chess;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameModule;
import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** The game around the board: turns, every way a game ends, draw claims and offers, and clocks. */
class ChessModuleTest {

    private static final String W = "white-player";
    private static final String B = "black-player";
    private static final ChessConfig CONFIG = new ChessConfig(60, 2);
    private final ChessModule module = new ChessModule();

    // ---------------------------------------------------------------- helpers

    private static ChessState start(String fen) {
        return ChessModule.start(W, B, CONFIG, Position.fromFen(fen));
    }

    private static ChessState start() {
        return start(Position.START_FEN);
    }

    private ChessState act(ChessState s, String actor, String type, Map<String, Object> data) {
        return (ChessState) module.onPlayerAction(s, PlayerAction.of(actor, type, data));
    }

    private ChessState act(ChessState s, String actor, String type) {
        return act(s, actor, type, Map.of());
    }

    private static Map<String, Object> moveData(String uci) {
        Map<String, Object> data = new HashMap<>();
        data.put("from", uci.substring(0, 2));
        data.put("to", uci.substring(2, 4));
        if (uci.length() == 5) {
            data.put("promotion", uci.substring(4));
        }
        return data;
    }

    private static String toMove(ChessState s) {
        return s.playerOf(s.position.sideToMove());
    }

    /** Plays UCI moves for whichever side is to move. */
    private ChessState play(ChessState s, String... ucis) {
        for (String uci : ucis) {
            s = act(s, toMove(s), "MOVE", moveData(uci));
        }
        return s;
    }

    private static GameEvent last(ChessState s, String type) {
        return s.events.stream().filter(e -> e.type().equals(type)).reduce((a, b) -> b)
                .orElseThrow(() -> new AssertionError("no " + type + " event"));
    }

    private static void assertResult(ChessState s, String winningSide, String reason) {
        assertThat(s.finished()).isTrue();
        assertThat(s.win.winningSide()).isEqualTo(winningSide);
        assertThat(s.resultReason).isEqualTo(reason);
        assertThat(last(s, "GAME_OVER").payload()).containsEntry("reason", reason).containsEntry("winningSide", winningSide);
    }

    private static void assertViolation(Runnable action, String code) {
        assertThatThrownBy(action::run).isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", code);
    }

    // The four knight moves that bring the start position back.
    private static final String[] KNIGHT_SHUFFLE = {"g1f3", "g8f6", "f3g1", "f6g8"};

    // ---------------------------------------------------------------- tests

    @Nested
    class Setup {

        @Test
        void twoPlayersGetOneColourEachAndWhiteStarts() {
            ChessState s = (ChessState) module.initialState(List.of("p1", "p2"), CONFIG, RandomSource.seeded(7));
            assertThat(List.of(s.white, s.black)).containsExactlyInAnyOrder("p1", "p2");
            assertThat(s.phase).isEqualTo("TurnW");
            assertThat(s.whiteClockMs).isEqualTo(60_000);
            assertThat(s.blackClockMs).isEqualTo(60_000);
            assertThat(module.runningClockMs(s)).hasValue(60_000);
            assertThat(module.playersToAct(s)).containsExactly(s.white);
        }

        @Test
        void needsExactlyTwoPlayers() {
            assertViolation(() -> module.initialState(List.of("solo"), CONFIG, RandomSource.seeded(1)), "NEEDS_TWO_PLAYERS");
        }

        @Test
        void configRejectsSillyTimeControls() {
            assertThatThrownBy(() -> new ChessConfig(10, 0)).isInstanceOf(IllegalArgumentException.class);
            assertThatThrownBy(() -> new ChessConfig(600, -1)).isInstanceOf(IllegalArgumentException.class);
        }
    }

    @Nested
    class Turns {

        @Test
        void aMoveHandsTheTurnOver() {
            ChessState s = play(start(), "e2e4");
            assertThat(s.phase).isEqualTo("TurnB");
            assertThat(s.round).isEqualTo(2);
            assertThat(s.sanMoves).containsExactly("e4");
            assertThat(last(s, "MOVE_PLAYED").payload())
                    .containsEntry("san", "e4").containsEntry("from", "e2").containsEntry("to", "e4");
            assertThat(module.playersToAct(s)).containsExactly(B);
        }

        @Test
        void refusesMovesThatAreNotTheActorsToMake() {
            ChessState s = start();
            assertViolation(() -> act(s, B, "MOVE", moveData("e7e5")), "NOT_YOUR_TURN");
            assertViolation(() -> act(s, "spectator", "MOVE", moveData("e2e4")), "NOT_A_PLAYER");
            assertViolation(() -> act(s, W, "MOVE", moveData("e7e5")), "NOT_YOUR_PIECE");
            assertViolation(() -> act(s, W, "MOVE", moveData("e2e5")), "ILLEGAL_MOVE");
            assertViolation(() -> act(s, W, "MOVE", Map.of("from", "z9", "to", "e4")), "BAD_SQUARE");
        }

        @Test
        void aMoveThatLeavesTheKingInCheckIsRefused() {
            ChessState s = start("4k3/8/8/8/4r3/8/8/4K3 w - - 0 1");
            assertThatThrownBy(() -> act(s, W, "MOVE", moveData("e1e2")))
                    .isInstanceOf(RuleViolation.class)
                    .hasMessageContaining("check");
        }

        @Test
        void replayingAnActionIdIsANoOp() {
            ChessState s = start();
            PlayerAction once = new PlayerAction("same-id", W, "MOVE", moveData("e2e4"));
            ChessState after = (ChessState) module.onPlayerAction(s, once);
            assertThat(module.onPlayerAction(after, once)).isSameAs(after);
        }

        @Test
        void nothingHappensAfterTheGameIsOver() {
            ChessState over = act(start(), W, "RESIGN");
            assertThat(act(over, B, "MOVE", moveData("e7e5"))).isSameAs(over);
        }
    }

    @Nested
    class Promotion {

        @ParameterizedTest
        @CsvSource({"q, wQ", "r, wR", "b, wB", "n, wN", "queen, wQ", "knight, wN"})
        void eachChoiceBecomesThatPiece(String choice, String code) {
            Map<String, Object> data = moveData("a7a8");
            data.put("promotion", choice);
            ChessState s = act(start("8/P7/8/8/8/8/8/k6K w - - 0 1"), W, "MOVE", data);
            assertThat(s.position.at(Square.parse("a8")).code()).isEqualTo(code);
            assertThat(last(s, "MOVE_PLAYED").payload().get("promotion")).isNotNull();
        }

        @Test
        void aPromotionWithoutAChoiceIsRefused() {
            assertViolation(() -> act(start("8/P7/8/8/8/8/8/k6K w - - 0 1"), W, "MOVE", moveData("a7a8")),
                    "PROMOTION_REQUIRED");
        }

        @Test
        void choosingAPromotionOnAnOrdinaryMoveIsRefused() {
            Map<String, Object> data = moveData("e2e4");
            data.put("promotion", "q");
            assertViolation(() -> act(start(), W, "MOVE", data), "BAD_PROMOTION");
        }

        @Test
        void aKingIsNotAPromotionChoice() {
            Map<String, Object> data = moveData("a7a8");
            data.put("promotion", "k");
            assertViolation(() -> act(start("8/P7/8/8/8/8/8/k6K w - - 0 1"), W, "MOVE", data), "BAD_PROMOTION");
        }

        @Test
        void theViewOffersTheSquareOnceAndLetsTheClientAsk() {
            ChessState s = start("8/P7/8/8/8/8/8/k6K w - - 0 1");
            @SuppressWarnings("unchecked")
            Map<String, List<String>> legal = (Map<String, List<String>>) module.broadcastState(s).data().get("legalMoves");
            assertThat(legal.get("a7")).containsExactly("a8");
        }
    }

    @Nested
    class DecisiveEndings {

        @Test
        void checkmate() {
            ChessState s = play(start(), "f2f3", "e7e5", "g2g4", "d8h4");
            assertResult(s, "black", "checkmate");
            assertThat(s.sanMoves).endsWith("Qh4#");
            assertThat(s.win.perPlayerOutcome()).containsEntry(B, "won").containsEntry(W, "lost");
            assertThat(module.playersToAct(s)).isEmpty();
            assertThat(module.runningClockMs(s)).isEmpty();
        }

        @Test
        void resignationAtAnyTime() {
            ChessState s = act(start(), B, "RESIGN");
            assertResult(s, "white", "resignation");
        }

        @Test
        void aForfeitIsRecordedAsSuch() {
            assertResult(act(start(), W, "FORFEIT"), "black", "forfeit");
        }

        @Test
        void spectatorsCannotResign() {
            assertViolation(() -> act(start(), "spectator", "RESIGN"), "NOT_A_PLAYER");
        }
    }

    @Nested
    class AutomaticDraws {

        @Test
        void stalemate() {
            assertResult(play(start("k7/8/1Q6/8/8/8/8/7K w - - 0 1"), "b6c7"), "draw", "stalemate");
        }

        @Test
        void aCaptureLeavingADeadPosition() {
            ChessState s = play(start("8/8/8/8/8/2k5/3n4/K1B5 w - - 0 1"), "c1d2");
            assertResult(s, "draw", "dead_position");
        }

        @Test
        void theSeventyFiveMoveRule() {
            ChessState s = play(start("7k/8/8/8/8/8/R7/K7 w - - 149 100"), "a2b2");
            assertResult(s, "draw", "seventy_five_move_rule");
        }

        @Test
        void checkmateOnTheSeventyFifthMoveStillWins() {
            ChessState s = play(start("7k/8/6K1/8/8/8/8/R7 w - - 149 100"), "a1a8");
            assertResult(s, "white", "checkmate");
        }

        @Test
        void fivefoldRepetition() {
            ChessState s = start();
            for (int cycle = 0; cycle < 3; cycle++) {
                s = play(s, KNIGHT_SHUFFLE);
            }
            assertThat(s.finished()).as("four occurrences is not yet automatic").isFalse();
            s = play(s, KNIGHT_SHUFFLE);
            assertResult(s, "draw", "fivefold_repetition");
        }
    }

    @Nested
    class ClaimedDraws {

        @Test
        void threefoldRepetitionOnTheBoard() {
            ChessState s = play(start(), KNIGHT_SHUFFLE);
            assertViolation(() -> act(play(start(), KNIGHT_SHUFFLE), W, "CLAIM_DRAW"), "CLAIM_INVALID");
            s = play(s, KNIGHT_SHUFFLE);
            assertThat(module.broadcastState(s).data()).containsEntry("canClaimThreefold", true);
            assertResult(act(s, W, "CLAIM_DRAW"), "draw", "threefold_repetition");
        }

        @Test
        void onlyThePlayerToMoveMayClaim() {
            ChessState s = play(play(start(), KNIGHT_SHUFFLE), KNIGHT_SHUFFLE);
            assertViolation(() -> act(s, B, "CLAIM_DRAW"), "NOT_YOUR_TURN");
        }

        @Test
        void threefoldByAnnouncingTheMoveThatRepeats() {
            ChessState s = play(play(start(), KNIGHT_SHUFFLE), "g1f3", "g8f6", "f3g1");
            ChessState drawn = act(s, B, "CLAIM_DRAW", moveData("f6g8"));
            assertResult(drawn, "draw", "threefold_repetition");
            assertThat(drawn.sanMoves).as("the announced move is played").endsWith("Ng8");
        }

        @Test
        void aClaimWithAMoveThatDoesNotRepeatPlaysNothing() {
            ChessState s = play(play(start(), KNIGHT_SHUFFLE), "g1f3", "g8f6", "f3g1");
            assertViolation(() -> act(s, B, "CLAIM_DRAW", moveData("e7e5")), "CLAIM_INVALID");
            assertThat(s.sanMoves).hasSize(7);
        }

        @Test
        void lostCastlingRightsMakeADifferentPosition() {
            // After Ke2/Ke7/Ke1/Ke8 the pieces stand where they did after
            // 1.e4 e5, but neither side can castle — not a repetition.
            ChessState s = play(start(), "e2e4", "e7e5");
            String[] kingWalk = {"e1e2", "e8e7", "e2e1", "e7e8"};
            s = play(s, kingWalk);
            s = play(s, kingWalk);
            assertThat(s.repetitionCount()).as("two occurrences of the no-castling position").isEqualTo(2);
            ChessState finalS = s;
            assertViolation(() -> act(finalS, W, "CLAIM_DRAW"), "CLAIM_INVALID");
        }

        @Test
        void fiftyMoveRuleOnTheBoard() {
            ChessState s = start("7k/8/8/8/8/8/R7/K7 b - - 100 80");
            assertThat(module.broadcastState(s).data()).containsEntry("canClaimFiftyMove", true);
            assertResult(act(s, B, "CLAIM_DRAW"), "draw", "fifty_move_rule");
        }

        @Test
        void fiftyMoveRuleNotYetDue() {
            assertViolation(() -> act(start("7k/8/8/8/8/8/R7/K7 b - - 99 80"), B, "CLAIM_DRAW"), "CLAIM_INVALID");
        }

        @Test
        void fiftyMoveRuleByAnnouncingTheFiftiethMove() {
            ChessState s = start("7k/8/8/8/8/8/R7/K7 w - - 99 80");
            assertResult(act(s, W, "CLAIM_DRAW", moveData("a2b2")), "draw", "fifty_move_rule");
        }

        @Test
        void announcingAPawnMoveResetsTheCountSoTheClaimFails() {
            assertViolation(() -> act(start("7k/8/8/8/8/P7/R7/K7 w - - 99 80"), W, "CLAIM_DRAW", moveData("a3a4")),
                    "CLAIM_INVALID");
        }

        @Test
        void anAnnouncedMoveThatMatesWinsInsteadOfDrawing() {
            ChessState s = act(start("7k/8/6K1/8/8/8/8/R7 w - - 99 100"), W, "CLAIM_DRAW", moveData("a1a8"));
            assertResult(s, "white", "checkmate");
        }
    }

    @Nested
    class DrawOffers {

        @Test
        void offeredAndAccepted() {
            ChessState s = act(start(), W, "OFFER_DRAW");
            assertThat(s.pendingDrawOffer).isEqualTo(W);
            assertResult(act(s, B, "ACCEPT_DRAW"), "draw", "agreement");
        }

        @Test
        void youCannotAcceptYourOwnOfferOrANonexistentOne() {
            ChessState offered = act(start(), W, "OFFER_DRAW");
            assertViolation(() -> act(offered, W, "ACCEPT_DRAW"), "NO_DRAW_OFFER");
            assertViolation(() -> act(start(), B, "ACCEPT_DRAW"), "NO_DRAW_OFFER");
        }

        @Test
        void declinedExplicitly() {
            ChessState s = act(act(start(), W, "OFFER_DRAW"), B, "DECLINE_DRAW");
            assertThat(s.pendingDrawOffer).isNull();
            assertThat(last(s, "DRAW_DECLINED").payload()).containsEntry("implicit", false);
        }

        @Test
        void answeringWithAMoveDeclinesIt() {
            ChessState s = play(act(play(start(), "e2e4"), W, "OFFER_DRAW"), "e7e5");
            assertThat(s.pendingDrawOffer).isNull();
            assertThat(last(s, "DRAW_DECLINED").payload()).containsEntry("implicit", true).containsEntry("by", B);
        }

        @Test
        void theOffererMovingLeavesItStanding() {
            ChessState s = play(act(start(), W, "OFFER_DRAW"), "e2e4");
            assertThat(s.pendingDrawOffer).isEqualTo(W);
            assertResult(act(s, B, "ACCEPT_DRAW"), "draw", "agreement");
        }

        @Test
        void oneOfferPerMove() {
            ChessState declined = act(act(start(), W, "OFFER_DRAW"), B, "DECLINE_DRAW");
            assertViolation(() -> act(declined, W, "OFFER_DRAW"), "DRAW_ALREADY_OFFERED");
            ChessState afterMoves = play(declined, "e2e4", "e7e5");
            assertThat(act(afterMoves, W, "OFFER_DRAW").pendingDrawOffer).isEqualTo(W);
        }

        @Test
        void onlyOneOfferCanBePending() {
            ChessState offered = act(start(), W, "OFFER_DRAW");
            assertViolation(() -> act(offered, B, "OFFER_DRAW"), "DRAW_ALREADY_PENDING");
        }
    }

    @Nested
    class Clocks {

        private ChessState stampedMove(ChessState s, String uci, long remainingMs) {
            Map<String, Object> data = moveData(uci);
            data.put(GameModule.CLOCK_REMAINING_KEY, remainingMs);
            return act(s, toMove(s), "MOVE", data);
        }

        @Test
        void aMoveBanksTheMeasuredTimePlusTheIncrement() {
            ChessState s = stampedMove(start(), "e2e4", 50_000);
            assertThat(s.whiteClockMs).isEqualTo(52_000);
            assertThat(s.blackClockMs).isEqualTo(60_000);
            assertThat(module.runningClockMs(s)).as("now black's clock runs").hasValue(60_000);
            assertThat(last(s, "TURN_STARTED").payload()).containsEntry("whiteMs", 52_000L);
        }

        @Test
        void withoutAMeasurementOnlyTheIncrementIsAdded() {
            assertThat(play(start(), "e2e4").whiteClockMs).isEqualTo(62_000);
        }

        @Test
        void aMoveArrivingAfterTheFlagFellLosesOnTime() {
            ChessState s = stampedMove(start(), "e2e4", 0);
            assertResult(s, "black", "timeout");
            assertThat(s.sanMoves).as("the late move is not played").isEmpty();
            assertThat(s.whiteClockMs).isZero();
        }

        @Test
        void anyActionCarriesTheRunningClockSoAnOpponentsOfferCanRevealAFallenFlag() {
            Map<String, Object> data = new HashMap<>();
            data.put(GameModule.CLOCK_REMAINING_KEY, 0L);
            assertResult(act(start(), B, "OFFER_DRAW", data), "black", "timeout");
        }

        @Test
        void theTimerElapsingIsALossOnTime() {
            GameState s = module.onPhaseElapsed(play(start(), "e2e4"), "TurnB");
            assertResult((ChessState) s, "white", "timeout");
        }

        @Test
        void aStaleTimerIsIgnored() {
            ChessState s = play(start(), "e2e4");
            assertThat(module.onPhaseElapsed(s, "TurnW")).isSameAs(s);
        }

        @Test
        void timeoutAgainstABareKingIsADraw() {
            ChessState s = start("4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1");
            assertResult((ChessState) module.onPhaseElapsed(s, "TurnW"), "draw", "timeout_vs_insufficient_material");
        }

        @Test
        void timeoutAgainstALoneKnightLosesWhenAMateIsStillPossible() {
            // Black's own queen could box their king in, so the knight can mate.
            ChessState s = start("4k3/3q4/8/8/8/8/8/1N2K3 b - - 0 1");
            assertResult((ChessState) module.onPhaseElapsed(s, "TurnB"), "white", "timeout");
        }
    }

    @Nested
    class View {

        @Test
        void carriesWhatAClientNeedsToDrawTheGame() {
            ChessState s = play(start(), "e2e4", "d7d5", "e4d5");
            Map<String, Object> view = module.broadcastState(s).data();
            assertThat(view).containsEntry("turn", "black")
                    .containsEntry("fen", s.position.fen())
                    .containsEntry("moves", List.of("e4", "d5", "exd5"))
                    .containsEntry("lastMove", Map.of("from", "e4", "to", "d5"))
                    .containsEntry("capturedByWhite", List.of("bP"))
                    .containsEntry("inCheck", false);
            @SuppressWarnings("unchecked")
            List<String> board = (List<String>) view.get("board");
            assertThat(board).hasSize(64);
            assertThat(board.get(Square.parse("d5"))).isEqualTo("wP");
            assertThat(module.visibleStateFor(s, B).data()).isEqualTo(view);
        }

        @Test
        void aFinishedGameOffersNoMoves() {
            ChessState s = act(start(), W, "RESIGN");
            assertThat(module.broadcastState(s).data())
                    .containsEntry("legalMoves", Map.of())
                    .containsEntry("winningSide", "black")
                    .containsEntry("resultReason", "resignation");
        }
    }
}
