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
        String winner, Set<String> eliminated, Set<String> actionIds, List<GameEvent> events, LudoConfig config
) implements GameState {
    public LudoState {
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
