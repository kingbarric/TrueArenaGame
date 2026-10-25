package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import app.truearena.game.ludo.LudoConfig;
import app.truearena.game.ludo.LudoModule;
import app.truearena.game.ludo.LudoState;
import app.truearena.game.ludo.LudoExpectimaxSearch;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/** Follows the server's legal move list, including either order of the two dice. */
public final class LudoBotAdapter implements GameBotAdapter {
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private String turnPlayer;
    private List<?> dice = List.of();
    private List<?> moves = List.of();
    private boolean finished;
    private boolean paused;
    private Map<String, Object> view = Map.of();

    @Override public String gameType() { return "ludo"; }

    @Override public Optional<BotPrompt> onFrame(String type, Map<String, Object> payload,
                                                  String botUserId, Difficulty difficulty) {
        if (!"SNAPSHOT".equals(type)) return Optional.empty();
        view = payload;
        turnPlayer = String.valueOf(payload.get("turnPlayer"));
        dice = payload.get("dice") instanceof List<?> list ? list : List.of();
        moves = payload.get("legalMoves") instanceof List<?> list ? list : List.of();
        finished = "Results".equals(payload.get("phase"));
        paused = Boolean.TRUE.equals(payload.get("paused"));
        if (paused || finished || !botUserId.equals(turnPlayer)) return Optional.empty();
        return Optional.of(new BotPrompt(
                "You are a Ludo Cyber Agent. Choose one legal token and die. Reply with JSON "
                        + "{\"token\":0,\"die\":6}. If no dice remain, reply ROLL. Difficulty: " + difficulty,
                "Available dice: " + dice + "; legal moves: " + moves));
    }

    @Override public Optional<PlayerAction> parseAction(String raw, String botUserId) {
        if (dice.isEmpty()) return Optional.of(PlayerAction.of(botUserId, "ROLL", Map.of()));
        if (raw == null) return Optional.empty();
        try {
            Map<?, ?> response = MAPPER.readValue(raw, Map.class);
            for (Object move : moves) {
                if (move instanceof Map<?, ?> m && m.get("token").equals(response.get("token"))
                        && m.get("die").equals(response.get("die"))) {
                    return Optional.of(PlayerAction.of(botUserId, "MOVE", Map.of(
                            "token", m.get("token"), "die", m.get("die"))));
                }
            }
        } catch (Exception ignored) {
            // A malformed model reply is handled by fallbackAction.
        }
        return Optional.empty();
    }

    @Override public Optional<PlayerAction> fallbackAction(String botUserId) {
        if (paused || finished || !botUserId.equals(turnPlayer)) return Optional.empty();
        if (dice.isEmpty()) return Optional.of(PlayerAction.of(botUserId, "ROLL", Map.of()));
        if (moves.isEmpty() || !(moves.get(0) instanceof Map<?, ?> m)) return Optional.empty();
        return Optional.of(PlayerAction.of(botUserId, "MOVE", Map.of("token", m.get("token"), "die", m.get("die"))));
    }

    @Override public Optional<PlayerAction> decideLocally(String botId, Difficulty level) {
        if (paused || finished || !botId.equals(turnPlayer) || dice.isEmpty() || moves.isEmpty()) return fallbackAction(botId);
        if (level != Difficulty.EASY) {
            var limits = level == Difficulty.HARD ? new LudoExpectimaxSearch.Limits(2, 3, 20000, 300)
                    : new LudoExpectimaxSearch.Limits(1, 2, 6000, 100);
            var decision = LudoExpectimaxSearch.choose(view, botId, limits);
            if (decision.action().isPresent()) return decision.action();
        }
        List<Map<?, ?>> legal = moves.stream().filter(Map.class::isInstance).<Map<?, ?>>map(x -> (Map<?, ?>) x).toList();
        if (legal.isEmpty()) return Optional.empty();
        Map<?, ?> chosen = BotChoices.choose(legal, level, move -> score(botId, move, level));
        return Optional.of(PlayerAction.of(botId, "MOVE", Map.of("token", chosen.get("token"), "die", chosen.get("die"))));
    }

    @SuppressWarnings("unchecked")
    private double score(String botId, Map<?, ?> move, Difficulty level) {
        if (!(view.get("pieces") instanceof Map<?, ?>) || !(view.get("players") instanceof List<?>)) return 0;
        List<String> players = (List<String>) view.get("players");
        Map<String, List<Integer>> pieces = (Map<String, List<Integer>>) view.get("pieces");
        List<Integer> remaining = dice.stream().map(x -> ((Number) x).intValue()).toList();
        // Only MOVE is simulated: no server seed or future dice are available to this bot.
        LudoState before = new LudoState("Turn", 1, players, pieces, players.indexOf(botId), remaining, 0, 0,
                0, null, Set.of(), Set.of(), List.of(), LudoConfig.defaults());
        LudoState after = (LudoState) new LudoModule().onPlayerAction(before,
                PlayerAction.of(botId, "MOVE", Map.of("token", move.get("token"), "die", move.get("die"))));
        if (after.finished()) return 10000;
        double score = 0;
        for (int i = 0; i < pieces.get(botId).size(); i++) {
            int from = pieces.get(botId).get(i), to = after.pieces().get(botId).get(i);
            score += to - from;
            if (to == 56 && from != 56) score += 150;
            if (from == -1 && to >= 0) score += 18;
            if (level != Difficulty.EASY) score += safety(after, botId, to) - safety(before, botId, from);
        }
        for (String opponent : players) {
            if (opponent.equals(botId)) continue;
            for (int i = 0; i < pieces.get(opponent).size(); i++) {
                if (pieces.get(opponent).get(i) >= 0 && after.pieces().get(opponent).get(i) == -1)
                    score += 100 + pieces.get(opponent).get(i);
            }
        }
        return score;
    }

    private double safety(LudoState state, String player, int progress) {
        if (progress < 0 || progress == 56) return 0;
        if (progress > 50) return 25;
        int square = square(state, player, progress);
        if (Set.of(0, 8, 13, 21, 26, 34, 39, 47).contains(square)) return 15;
        double risk = 0;
        for (String opponent : state.players()) {
            if (opponent.equals(player)) continue;
            for (int position : state.pieces().get(opponent)) {
                if (position < 0 || position > 50) continue;
                int distance = Math.floorMod(square - square(state, opponent, position), 52);
                if (distance > 0 && distance <= 6 && position + distance <= 50) risk += 12 + progress * .3;
            }
        }
        return -risk;
    }

    private int square(LudoState state, String player, int progress) {
        int seat = state.players().indexOf(player);
        if (state.players().size() == 2) seat *= 2;
        return (seat * 13 + progress) % 52;
    }
}
