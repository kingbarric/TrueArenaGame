package app.truearena.game.ludo;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.WinResult;

import java.util.List;
import java.util.Map;
import java.util.Set;

public record LudoState(
        String phase, int round, List<String> players, Map<String, List<Integer>> pieces,
        int turnIndex, List<Integer> dice, int rollCount, int bonusRolls, long seed,
        String winner, Set<String> eliminated, Set<String> actionIds, List<GameEvent> events, LudoConfig config,
        Undo undo
) implements GameState {

    /**
     * Taking back a turn. {@code start*}: the turn under way, as it stood
     * right after the roll. {@code last*}: the previous player's finished
     * turn — what an agreed undo puts back (same pieces, same dice) — until
     * the next player rolls. {@code pending}: the player asking.
     */
    public record Undo(Map<String, List<Integer>> startPieces, List<Integer> startDice, int startBonus,
                       Map<String, List<Integer>> lastPieces, List<Integer> lastDice, int lastBonus,
                       int lastTurnIndex, String lastMover, String pending) {
        public static final Undo NONE = new Undo(null, null, 0, null, null, 0, -1, null, null);
    }

    public LudoState(String phase, int round, List<String> players, Map<String, List<Integer>> pieces,
                     int turnIndex, List<Integer> dice, int rollCount, int bonusRolls, long seed,
                     String winner, Set<String> eliminated, Set<String> actionIds, List<GameEvent> events,
                     LudoConfig config) {
        this(phase, round, players, pieces, turnIndex, dice, rollCount, bonusRolls, seed, winner, eliminated,
                actionIds, events, config, Undo.NONE);
    }

    public LudoState withUndo(Undo next) {
        return new LudoState(phase, round, players, pieces, turnIndex, dice, rollCount, bonusRolls, seed, winner,
                eliminated, actionIds, events, config, next);
    }

    public LudoState {
        if (undo == null) undo = Undo.NONE;
        players = List.copyOf(players);
        pieces = Map.copyOf(pieces);
        dice = List.copyOf(dice);
        eliminated = Set.copyOf(eliminated);
        actionIds = Set.copyOf(actionIds);
        events = List.copyOf(events);
    }

    @Override public boolean finished() { return winner != null; }
    public String turnPlayer() { return players.get(turnIndex); }

    public WinResult winResult() {
        return new WinResult(winner, players.stream().collect(java.util.stream.Collectors.toMap(
                p -> p, p -> p.equals(winner) ? "win" : "lose")));
    }
}
