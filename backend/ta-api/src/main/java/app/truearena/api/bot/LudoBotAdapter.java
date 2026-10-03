package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.List;
import java.util.Map;
import java.util.Optional;

/** Follows the server's legal move list, including either order of the two dice. */
public final class LudoBotAdapter implements GameBotAdapter {
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private String turnPlayer;
    private List<?> dice = List.of();
    private List<?> moves = List.of();
    private boolean finished;

    @Override public String gameType() { return "ludo"; }

    @Override public Optional<BotPrompt> onFrame(String type, Map<String, Object> payload,
                                                  String botUserId, Difficulty difficulty) {
        if (!"SNAPSHOT".equals(type)) return Optional.empty();
        turnPlayer = String.valueOf(payload.get("turnPlayer"));
        dice = payload.get("dice") instanceof List<?> list ? list : List.of();
        moves = payload.get("legalMoves") instanceof List<?> list ? list : List.of();
        finished = "Results".equals(payload.get("phase"));
        if (finished || !botUserId.equals(turnPlayer)) return Optional.empty();
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
        if (dice.isEmpty()) return Optional.of(PlayerAction.of(botUserId, "ROLL", Map.of()));
        if (moves.isEmpty() || !(moves.get(0) instanceof Map<?, ?> m)) return Optional.empty();
        return Optional.of(PlayerAction.of(botUserId, "MOVE", Map.of("token", m.get("token"), "die", m.get("die"))));
    }
}
