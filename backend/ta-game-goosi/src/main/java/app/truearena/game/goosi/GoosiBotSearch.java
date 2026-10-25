package app.truearena.game.goosi;

import app.truearena.engine.GameState;
import app.truearena.engine.GameTreeSearch;
import app.truearena.engine.PlayerAction;

import java.util.List;
import java.util.Map;
import java.util.Optional;

/** Relay and Oware share search infrastructure, but all sowing/capture rules come from GoosiModule. */
public final class GoosiBotSearch {
    public static Optional<PlayerAction> choose(int[] pits, String[] owner, List<String> players,
            Map<String, Integer> scores, String mode, String player, int depth, long millis) {
        if (players.size() != 2 || !players.contains(player)) return Optional.empty();
        GoosiState.Draft d = new GoosiState.Draft();
        d.pits = pits.clone(); d.owner = owner.clone(); d.players = players;
        d.scores = players.stream().mapToInt(id -> scores.getOrDefault(id, 0)).toArray();
        d.turnIndex = players.indexOf(player); d.phase = "TurnP" + d.turnIndex; d.round = 1;
        d.config = new GoosiConfig(4, 45, mode);
        GoosiModule game = new GoosiModule();
        return GameTreeSearch.choose(game, d.build(), player, state -> legal(game, state),
                state -> evaluate((GoosiState) state, player), depth, millis);
    }

    @SuppressWarnings("unchecked")
    private static List<PlayerAction> legal(GoosiModule game, GameState state) {
        if (state.finished()) return List.of();
        String actor = game.playersToAct(state).iterator().next();
        List<Integer> pits = (List<Integer>) game.visibleStateFor(state, actor).data().get("legalPits");
        return pits.stream().map(pit -> PlayerAction.of(actor, "SOW", Map.of("pit", pit))).toList();
    }

    private static double evaluate(GoosiState s, String player) {
        int index = s.players.indexOf(player);
        int advantage = s.scores[index] - s.scores[1 - index];
        if (s.finished()) return Math.signum(advantage) * 100000;
        double score = advantage * 100;
        for (int i = 0; i < 12; i++) {
            double mobility = s.pits[i] > 0 ? 2 : 0;
            score += player.equals(s.owner[i]) ? mobility : -mobility;
        }
        return score;
    }

    private GoosiBotSearch() {}
}
