package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** A private-hand bot for Whot. The public table never contains its cards. */
public final class WhotBotAdapter implements GameBotAdapter {
    private static final SecureRandom RNG = new SecureRandom();
    private static final Pattern CARD = Pattern.compile("\\\"card\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"");
    private static final Pattern SHAPE = Pattern.compile("\\\"shape\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"");

    private final List<String> hand = new ArrayList<>();
    private final List<String> players = new ArrayList<>();
    private Map<String, Object> rules = Map.of();
    private String phase = "Deal", turnPlayer, topCard = "", activeShape = "";
    private int pendingPick;
    private boolean finished;

    @Override public String gameType() { return "whot"; }

    @Override
    public Optional<BotPrompt> onFrame(String type, Map<String, Object> payload, String botId, Difficulty difficulty) {
        switch (type) {
            case "SNAPSHOT" -> applySnapshot(payload);
            case "EVENT" -> applyEvent(payload);
            case "PHASE" -> { phase = String.valueOf(payload.getOrDefault("phase", phase)); return Optional.empty(); }
            default -> { return Optional.empty(); }
        }
        if (finished || !("Turn".equals(phase) || "Waiting".equals(phase)) || !botId.equals(turnPlayer)) return Optional.empty();
        return Optional.of(new BotPrompt(
                "You are playing Whot. Match the top card by shape or number. If a 2 is owed, "
                        + "only answer with a 2 when stacking is enabled. Whot is wild and needs a shape. "
                        + "Reply only with JSON: {\"action\":\"PLAY\",\"card\":\"circle-5\",\"shape\":\"circle\"} "
                        + "or {\"action\":\"DRAW\"}. Difficulty: " + difficulty.name().toLowerCase(),
                "top=" + topCard + ", activeShape=" + activeShape + ", pendingPick=" + pendingPick + ", hand=" + hand + ", legal=" + legalCards()));
    }

    @SuppressWarnings("unchecked")
    private void applySnapshot(Map<String, Object> p) {
        phase = String.valueOf(p.getOrDefault("phase", phase));
        turnPlayer = string(p.get("turnPlayer"));
        topCard = String.valueOf(p.getOrDefault("topCard", topCard));
        activeShape = String.valueOf(p.getOrDefault("activeShape", activeShape));
        pendingPick = number(p.get("pendingPick"));
        finished = "Results".equals(phase);
        Object rawPlayers = p.get("players");
        if (rawPlayers instanceof List<?> list) { players.clear(); list.forEach(x -> players.add(String.valueOf(x))); }
        Object rawHand = p.get("yourHand");
        if (rawHand instanceof List<?> list) { hand.clear(); list.forEach(x -> hand.add(String.valueOf(x))); }
        Object rawRules = p.get("rules");
        if (rawRules instanceof Map<?, ?> map) { rules = new LinkedHashMap<>(); map.forEach((k, v) -> rules.put(String.valueOf(k), v)); }
    }

    @SuppressWarnings("unchecked")
    private void applyEvent(Map<String, Object> envelope) {
        String type = String.valueOf(envelope.get("type"));
        Map<String, Object> d = envelope.get("data") instanceof Map<?, ?> map ? (Map<String, Object>) map : Map.of();
        if ("GAME_STARTED".equals(type)) phase = "Deal";
        if ("TURN_STARTED".equals(type)) {
            phase = "Turn"; turnPlayer = string(d.get("player"));
            topCard = String.valueOf(d.getOrDefault("topCard", topCard));
            activeShape = String.valueOf(d.getOrDefault("activeShape", activeShape));
            pendingPick = number(d.get("pendingPick"));
        }
        if ("GAME_OVER".equals(type)) finished = true;
    }

    private List<String> legalCards() { return hand.stream().filter(this::matches).toList(); }
    private boolean matches(String card) {
        String[] parts = card.split("-", 2);
        if (pendingPick > 0) return "2".equals(parts[1]) && on("pickTwo") && on("pickTwoStacking");
        return "whot".equals(parts[0]) || parts[0].equals(activeShape)
                || (!topCard.isBlank() && parts[1].equals(topCard.substring(topCard.lastIndexOf('-') + 1)));
    }

    @Override
    public Optional<PlayerAction> parseAction(String raw, String botId) {
        if (raw == null) return Optional.empty();
        if (raw.toLowerCase().contains("draw")) return Optional.of(PlayerAction.of(botId, "DRAW", Map.of()));
        Matcher card = CARD.matcher(raw);
        if (!card.find() || !hand.contains(card.group(1)) || !matches(card.group(1))) return Optional.empty();
        Map<String, Object> data = new LinkedHashMap<>(); data.put("card", card.group(1));
        if (card.group(1).startsWith("whot-")) {
            Matcher shape = SHAPE.matcher(raw); data.put("shape", shape.find() ? shape.group(1) : bestShape());
        }
        return Optional.of(PlayerAction.of(botId, "PLAY", data));
    }

    @Override
    public Optional<PlayerAction> fallbackAction(String botId) {
        List<String> legal = legalCards();
        if (legal.isEmpty()) return Optional.of(PlayerAction.of(botId, "DRAW", Map.of()));
        String card = legal.get(RNG.nextInt(legal.size()));
        Map<String, Object> data = new LinkedHashMap<>(); data.put("card", card);
        if (card.startsWith("whot-")) data.put("shape", bestShape());
        return Optional.of(PlayerAction.of(botId, "PLAY", data));
    }

    private String bestShape() {
        String best = "circle"; int max = -1;
        for (String shape : List.of("circle", "triangle", "cross", "square", "star")) {
            int count = (int) hand.stream().filter(c -> c.startsWith(shape + "-")).count();
            if (count > max) { max = count; best = shape; }
        }
        return best;
    }
    private boolean on(String key) { return Boolean.TRUE.equals(rules.get(key)); }
    private static int number(Object x) { return x instanceof Number n ? n.intValue() : 0; }
    private static String string(Object x) { return x == null ? null : String.valueOf(x); }
}
