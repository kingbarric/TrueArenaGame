package app.truearena.game.ludo;

import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class LudoModuleTest {
    private final LudoModule module = new LudoModule();

    private LudoState start(int players) {
        return (LudoState) module.initialState(List.of("red", "green", "yellow", "blue").subList(0, players),
                LudoConfig.defaults(), RandomSource.seeded(41));
    }

    private LudoState state(LudoState base, Map<String, List<Integer>> pieces, List<Integer> dice) {
        return new LudoState("Turn", base.round(), base.players(), pieces, base.turnIndex(), dice,
                base.rollCount(), base.bonusRolls(), base.seed(), null, base.eliminated(), base.actionIds(), base.events(), base.config());
    }

    private LudoState act(LudoState state, String player, String type, Map<String, Object> data) {
        return (LudoState) module.onPlayerAction(state, PlayerAction.of(player, type, data));
    }

    @Test void seatsTwoThreeOrFourAndKeepsOppositeSeatsForTwo() {
        assertThat(module.broadcastState(start(2)).data().get("seats")).isEqualTo(List.of(0, 2));
        assertThat(module.broadcastState(start(3)).data().get("seats")).isEqualTo(List.of(0, 1, 2));
        assertThat(module.broadcastState(start(4)).data().get("seats")).isEqualTo(List.of(0, 1, 2, 3));
        assertThatThrownBy(() -> start(1)).isInstanceOf(RuleViolation.class);
    }

    @Test void twoPlayersMayChooseEightPiecesWhileLargerTablesUseFour() {
        LudoConfig eight = new LudoConfig(60, 8);
        LudoState two = (LudoState) module.initialState(List.of("red", "yellow"), eight, RandomSource.seeded(41));
        assertThat(two.pieces().get("red")).hasSize(8).containsOnly(-1);
        assertThat(module.broadcastState(two).data().get("pieceCount")).isEqualTo(8);
        LudoState withDice = state(two, two.pieces(), List.of(6, 2));
        LudoState released = act(withDice, "red", "MOVE", Map.of("die", 6, "token", 7));
        assertThat(released.pieces().get("red").get(7)).isEqualTo(0);
        assertThat(module.broadcastState(released).data().get("legalMoves"))
                .isEqualTo(List.of(Map.of("die", 2, "token", 7)));
        LudoState advanced = act(released, "red", "MOVE", Map.of("die", 2, "token", 7));
        assertThat(advanced.pieces().get("red").get(7)).isEqualTo(2);

        LudoState three = (LudoState) module.initialState(List.of("red", "green", "yellow"), eight,
                RandomSource.seeded(41));
        assertThat(three.pieces().get("red")).hasSize(4);
        assertThatThrownBy(() -> new LudoConfig(60, 6)).isInstanceOf(IllegalArgumentException.class);
    }

    @Test void sixReleasesOneTokenThenOtherDieCanMoveSameOrDifferentToken() {
        LudoState s = state(start(2), start(2).pieces(), List.of(4, 6));
        LudoState beforeRelease = s;
        assertThatThrownBy(() -> act(beforeRelease, "red", "MOVE", Map.of("die", 4, "token", 0)))
                .isInstanceOf(RuleViolation.class);
        s = act(s, "red", "MOVE", Map.of("die", 6, "token", 0));
        assertThat(s.pieces().get("red")).containsExactly(0, -1, -1, -1);
        s = act(s, "red", "MOVE", Map.of("die", 4, "token", 0));
        assertThat(s.pieces().get("red")).containsExactly(4, -1, -1, -1);

        Map<String, List<Integer>> pieces = new LinkedHashMap<>(start(2).pieces());
        pieces.put("red", List.of(0, 7, -1, -1));
        s = state(start(2), pieces, List.of(2, 3));
        s = act(s, "red", "MOVE", Map.of("die", 2, "token", 0));
        s = act(s, "red", "MOVE", Map.of("die", 3, "token", 1));
        assertThat(s.pieces().get("red")).containsExactly(2, 10, -1, -1);
    }

    @Test void capturesOnOrdinarySquareButNotOnStar() {
        Map<String, List<Integer>> pieces = new LinkedHashMap<>(start(4).pieces());
        // Red progress 11 lands on absolute square 14; green progress 1 is there.
        pieces.put("red", List.of(11, -1, -1, -1));
        pieces.put("green", List.of(1, -1, -1, -1));
        LudoState result = act(state(start(4), pieces, List.of(3)), "red", "MOVE", Map.of("die", 3, "token", 0));
        assertThat(result.pieces().get("green")).containsExactly(-1, -1, -1, -1);
        assertThat(result.turnPlayer()).isEqualTo("green");
        assertThat(result.events().getLast().type()).isEqualTo("TURN_STARTED");

        pieces.put("red", List.of(5, -1, -1, -1));
        pieces.put("green", List.of(47, -1, -1, -1)); // absolute square 8
        result = act(state(start(4), pieces, List.of(3)), "red", "MOVE", Map.of("die", 3, "token", 0));
        assertThat(result.pieces().get("green").get(0)).isEqualTo(47);
    }

    @Test void oppositeTwoPlayerSeatsCaptureWithFourOrEightPieces() {
        LudoState four = start(2);
        Map<String, List<Integer>> pieces = new LinkedHashMap<>(four.pieces());
        // Red progress 14 and the opposite seat's progress 40 are both absolute square 14.
        pieces.put("red", List.of(11, -1, -1, -1));
        pieces.put("green", List.of(40, -1, -1, -1));
        LudoState captured = act(state(four, pieces, List.of(3)), "red", "MOVE",
                Map.of("die", 3, "token", 0));
        assertThat(captured.pieces().get("green")).containsOnly(-1);
        assertThat(captured.events().get(captured.events().size() - 2).payload().get("captured"))
                .isEqualTo(List.of("green:0"));

        LudoState eight = (LudoState) module.initialState(List.of("red", "green"),
                new LudoConfig(60, 8), RandomSource.seeded(41));
        pieces = new LinkedHashMap<>(eight.pieces());
        pieces.put("red", List.of(-1, -1, -1, -1, -1, -1, -1, 11));
        pieces.put("green", List.of(-1, -1, -1, -1, -1, -1, -1, 40));
        captured = act(state(eight, pieces, List.of(3)), "red", "MOVE",
                Map.of("die", 3, "token", 7));
        assertThat(captured.pieces().get("green")).containsOnly(-1);
        assertThat(captured.events().get(captured.events().size() - 2).payload().get("captured"))
                .isEqualTo(List.of("green:7"));
    }

    @Test void homeNeedsExactRollAndTimeoutSkipsRemainingDice() {
        Map<String, List<Integer>> pieces = new LinkedHashMap<>(start(2).pieces());
        pieces.put("red", List.of(54, 56, 56, 56));
        LudoState s = state(start(2), pieces, List.of(3, 2));
        LudoState beforeFinish = s;
        assertThatThrownBy(() -> act(beforeFinish, "red", "MOVE", Map.of("die", 3, "token", 0)))
                .isInstanceOf(RuleViolation.class);
        s = act(s, "red", "MOVE", Map.of("die", 2, "token", 0));
        assertThat(s.finished()).isTrue();
        assertThat(s.winner()).isEqualTo("red");

        LudoState elapsed = (LudoState) module.onPhaseElapsed(state(start(2), pieces, List.of(3, 2)), "Turn");
        assertThat(elapsed.turnPlayer()).isEqualTo("green");
        assertThat(elapsed.dice()).isEmpty();
    }

    @Test void serverRollIsDeterministicAndNeverAcceptsClientDice() {
        LudoState a = act(start(2), "red", "ROLL", Map.of("dice", List.of(6, 6)));
        LudoState b = act(start(2), "red", "ROLL", Map.of("dice", List.of(1, 1)));
        assertThat(a.events().get(1).payload().get("dice")).isEqualTo(b.events().get(1).payload().get("dice"));
    }

    @Test void rollRetainsBothDiceWhenSixUnlocksTheOtherDie() {
        LudoState rolled = null;
        for (long seed = 1; seed < 500; seed++) {
            LudoState fresh = (LudoState) module.initialState(List.of("red", "yellow"),
                    LudoConfig.defaults(), RandomSource.seeded(seed));
            LudoState candidate = act(fresh, "red", "ROLL", Map.of());
            if (candidate.dice().contains(6) && candidate.dice().stream().anyMatch(d -> d != 6)) {
                rolled = candidate;
                break;
            }
        }
        assertThat(rolled).isNotNull();
        int other = rolled.dice().stream().filter(d -> d != 6).findFirst().orElseThrow();
        assertThat(rolled.dice()).hasSize(2);
        assertThat(module.broadcastState(rolled).data().get("rolledDice")).isEqualTo(rolled.dice());
        assertThat(module.broadcastState(rolled).data().get("rollPlayer")).isEqualTo("red");
        LudoState released = act(rolled, "red", "MOVE", Map.of("die", 6, "token", 0));
        assertThat(released.dice()).containsExactly(other);
        assertThat(module.broadcastState(released).data().get("rolledDice")).isEqualTo(rolled.dice());
        assertThat(module.broadcastState(released).data().get("legalMoves"))
                .isEqualTo(List.of(Map.of("die", other, "token", 0)));
        LudoState passed = act(released, "red", "MOVE", Map.of("die", other, "token", 0));
        assertThat(module.broadcastState(passed).data().get("rolledDice")).isEqualTo(List.of());
    }

    @Test void opponentPairBlocksLandingAndAStartSquareIsSafe() {
        Map<String, List<Integer>> pieces = new LinkedHashMap<>(start(4).pieces());
        pieces.put("red", List.of(11, -1, -1, -1));
        pieces.put("green", List.of(1, 1, -1, -1));
        LudoState blocked = state(start(4), pieces, List.of(3));
        assertThatThrownBy(() -> act(blocked, "red", "MOVE", Map.of("die", 3, "token", 0)))
                .isInstanceOf(RuleViolation.class);

        pieces.put("red", List.of(10, -1, -1, -1));
        pieces.put("green", List.of(0, -1, -1, -1)); // green start, absolute square 13
        LudoState safe = act(state(start(4), pieces, List.of(3)), "red", "MOVE", Map.of("die", 3, "token", 0));
        assertThat(safe.pieces().get("green").get(0)).isEqualTo(0);
    }

    @Test void onlyDoubleSixRepeatsAndConsecutiveDoubleSixCanRepeatAgain() {
        LudoState singleSix = null;
        LudoState doubleSix = null;
        for (long seed = 1; seed < 5000 && (singleSix == null || doubleSix == null); seed++) {
            LudoState fresh = (LudoState) module.initialState(List.of("red", "yellow"),
                    LudoConfig.defaults(), RandomSource.seeded(seed));
            LudoState rolled = act(fresh, "red", "ROLL", Map.of());
            if (rolled.dice().equals(List.of(6, 6))) doubleSix = rolled;
            else if (rolled.dice().contains(6)) singleSix = rolled;
        }
        assertThat(singleSix).isNotNull();
        assertThat(doubleSix).isNotNull();
        assertThat(singleSix.bonusRolls()).isZero();
        assertThat(doubleSix.bonusRolls()).isEqualTo(1);

        int other = singleSix.dice().stream().filter(d -> d != 6).findFirst().orElseThrow();
        LudoState afterSingle = act(singleSix, "red", "MOVE", Map.of("die", 6, "token", 0));
        afterSingle = act(afterSingle, "red", "MOVE", Map.of("die", other, "token", 0));
        assertThat(afterSingle.turnPlayer()).isEqualTo("yellow");

        LudoState afterFirstSix = act(doubleSix, "red", "MOVE", Map.of("die", 6, "token", 0));
        LudoState repeated = act(afterFirstSix, "red", "MOVE", Map.of("die", 6, "token", 1));
        assertThat(repeated.turnPlayer()).isEqualTo("red");
        assertThat(repeated.events().getLast().type()).isEqualTo("BONUS_ROLL");

        LudoState anotherDoubleSix = new LudoState("Turn", repeated.round(), repeated.players(), repeated.pieces(), 0,
                List.of(6, 6), repeated.rollCount(), 1, repeated.seed(), null, Set.of(),
                repeated.actionIds(), repeated.events(), repeated.config());
        LudoState moved = act(anotherDoubleSix, "red", "MOVE", Map.of("die", 6, "token", 0));
        moved = act(moved, "red", "MOVE", Map.of("die", 6, "token", 1));
        assertThat(moved.turnPlayer()).isEqualTo("red");
        assertThat(moved.events().getLast().type()).isEqualTo("BONUS_ROLL");

        Map<String, List<Integer>> pieces = new LinkedHashMap<>(start(2).pieces());
        pieces.put("red", List.of(55, -1, -1, -1));
        LudoState home = act(state(start(2), pieces, List.of(1)), "red", "MOVE", Map.of("die", 1, "token", 0));
        assertThat(home.turnPlayer()).isEqualTo("green");
        assertThat(home.events().getLast().type()).isEqualTo("TURN_STARTED");
    }

    @Test void forfeitingOneOfFourKeepsTheRemainingMatchRunning() {
        LudoState base = start(4);
        LudoState afterRed = act(base, "red", "FORFEIT", Map.of());
        assertThat(afterRed.finished()).isFalse();
        assertThat(afterRed.turnPlayer()).isEqualTo("green");
        assertThat(afterRed.eliminated()).containsExactly("red");
        LudoState afterGreen = act(afterRed, "green", "FORFEIT", Map.of());
        assertThat(afterGreen.finished()).isFalse();
        LudoState afterYellow = act(afterGreen, "yellow", "FORFEIT", Map.of());
        assertThat(afterYellow.finished()).isTrue();
        assertThat(afterYellow.winner()).isEqualTo("blue");
    }

    @Test void timeoutSkipsAnEliminatedSeatAndActionIdsAreIdempotent() {
        LudoState base = start(3);
        LudoState redOut = act(base, "red", "FORFEIT", Map.of());
        LudoState greenTimesOut = (LudoState) module.onPhaseElapsed(redOut, "Turn");
        assertThat(greenTimesOut.turnPlayer()).isEqualTo("yellow");
        LudoState yellowTimesOut = (LudoState) module.onPhaseElapsed(greenTimesOut, "Turn");
        assertThat(yellowTimesOut.turnPlayer()).isEqualTo("green");

        PlayerAction action = new PlayerAction("same-id", "green", "ROLL", Map.of());
        LudoState once = (LudoState) module.onPlayerAction(yellowTimesOut, action);
        assertThat(module.onPlayerAction(once, action)).isSameAs(once);
        assertThatThrownBy(() -> module.onPlayerAction(yellowTimesOut,
                PlayerAction.of("yellow", "ROLL", Map.of()))).isInstanceOf(RuleViolation.class);
    }

    @Test void playerCanLeaveOutOfTurnWithoutInterruptingCurrentTurn() {
        LudoState base = start(4);
        LudoState after = act(base, "yellow", "FORFEIT", Map.of());
        assertThat(after.turnPlayer()).isEqualTo("red");
        assertThat(after.eliminated()).contains("yellow");
        assertThat(after.finished()).isFalse();
        LudoState elapsed = (LudoState) module.onPhaseElapsed(after, "Turn");
        assertThat(elapsed.turnPlayer()).isEqualTo("green");
    }

    // ---------------------------------------------------------------- playersToAct (push turn reminders)

    @Test void playersToActIsWhoeverIsOnTurn() {
        LudoState base = start(4);
        assertThat(module.playersToAct(base)).containsExactly("red");
    }

    @Test void playersToActIsEmptyOnceFinished() {
        LudoState base = start(4);
        LudoState won = new LudoState(base.phase(), base.round(), base.players(), base.pieces(),
                base.turnIndex(), base.dice(), base.rollCount(), base.bonusRolls(), base.seed(),
                "red", base.eliminated(), base.actionIds(), base.events(), base.config());
        assertThat(module.playersToAct(won)).isEmpty();
    }

    /** Red rolls and plays out the turn (always picking the first legal move), so it passes to green. */
    @SuppressWarnings("unchecked")
    private LudoState redPlaysATurn(LudoState s) {
        LudoState rolled = act(s, "red", "ROLL", Map.of());
        LudoState now = rolled;
        while (now.turnPlayer().equals("red") && !now.dice().isEmpty()) {
            var legal = (List<Map<String, Integer>>) module.broadcastState(now).data().get("legalMoves");
            var m = legal.getFirst();
            now = act(now, "red", "MOVE", Map.of("die", m.get("die"), "token", m.get("token")));
        }
        return now;
    }

    @Test void anAgreedUndoGivesTheTurnBackWithTheSameDice() {
        LudoState base = start(2);
        LudoState s = state(base, Map.of("red", List.of(5, 10, -1, -1), "green", List.of(-1, -1, -1, -1)), List.of());
        LudoState rolled = act(s, "red", "ROLL", Map.of());
        LudoState after = redPlaysATurn(s);
        assertThat(after.turnPlayer()).as("this seed passes the turn to green").isEqualTo("green");
        assertThat(module.broadcastState(after).data()).containsEntry("undoableBy", "red");
        assertThatThrownBy(() -> act(after, "green", "REQUEST_UNDO", Map.of())).isInstanceOf(RuleViolation.class);

        LudoState asked = act(after, "red", "REQUEST_UNDO", Map.of());
        assertThat(module.broadcastState(asked).data()).containsEntry("pendingUndo", "red");
        LudoState back = act(asked, "green", "ACCEPT_UNDO", Map.of());
        assertThat(back.turnPlayer()).isEqualTo("red");
        assertThat(back.pieces()).isEqualTo(s.pieces());
        assertThat(back.dice()).isEqualTo(rolled.dice());
        assertThat(module.broadcastState(back).data()).containsEntry("undoableBy", null);
    }

    @Test void theNextRollOrANoKeepsTheTurn() {
        LudoState base = start(2);
        LudoState s = state(base, Map.of("red", List.of(5, 10, -1, -1), "green", List.of(-1, -1, -1, -1)), List.of());
        LudoState after = redPlaysATurn(s);
        assertThat(after.turnPlayer()).isEqualTo("green");
        LudoState declined = act(act(after, "red", "REQUEST_UNDO", Map.of()), "green", "DECLINE_UNDO", Map.of());
        assertThat(declined.turnPlayer()).isEqualTo("green");
        assertThat(declined.undo().pending()).isNull();

        LudoState greenRolled = act(act(after, "red", "REQUEST_UNDO", Map.of()), "green", "ROLL", Map.of());
        assertThat(greenRolled.undo().pending()).isNull();
        assertThatThrownBy(() -> act(greenRolled, "red", "REQUEST_UNDO", Map.of())).isInstanceOf(RuleViolation.class);
    }
}
