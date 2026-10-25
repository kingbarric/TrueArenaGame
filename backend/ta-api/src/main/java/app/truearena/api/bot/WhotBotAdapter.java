package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import app.truearena.game.whot.WhotMonteCarloSearch;
import app.truearena.game.whot.WhotDiscardMemory;

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
    private boolean paused;
    private Map<String, Object> handSizes = Map.of();
    private Map<String, Object> view = Map.of();
    private final WhotTellBotStrategy tell = new WhotTellBotStrategy();
    private final WhotDiscardMemory discardMemory = new WhotDiscardMemory();

    @Override public String gameType() { return "whot"; }

    @Override
    public Optional<BotPrompt> onFrame(String type, Map<String, Object> payload, String botId, Difficulty difficulty) {
        switch (type) {
            case "SNAPSHOT" -> applySnapshot(payload);
            case "EVENT" -> applyEvent(payload);
            case "PHASE" -> { phase = String.valueOf(payload.getOrDefault("phase", phase)); return Optional.empty(); }
            default -> { return Optional.empty(); }
        }
        // The updated private hand arrives in a snapshot after public turn events.
        if (!"SNAPSHOT".equals(type) || paused || finished) return Optional.empty();
        if (view.get("pendingUndo") instanceof String requester && !requester.isEmpty())
            return undoResponse(botId).isPresent() ? Optional.of(new BotPrompt("", "undo response")) : Optional.empty();
        if (tellMode() && !tell.active(view, botId)) return Optional.empty();
        boolean signalAction = tellMode() && tell.action(view, botId, false).isPresent();
        if (!signalAction && (!("Turn".equals(phase) || "Waiting".equals(phase))
                || !botId.equals(turnPlayer))) return Optional.empty();
        return Optional.of(new BotPrompt(
                "You are playing Whot. Match the top card by shape or number. If a 2 is owed, "
                        + "only answer with a 2 when stacking is enabled. Whot is wild and needs a shape. "
                        + "Reply only with JSON: {\"action\":\"PLAY\",\"card\":\"circle-5\",\"shape\":\"circle\"} "
                        + "or {\"action\":\"DRAW\"}. Difficulty: " + difficulty.name().toLowerCase(),
                "top=" + topCard + ", activeShape=" + activeShape + ", pendingPick=" + pendingPick + ", hand=" + hand + ", legal=" + legalCards()));
    }

    @SuppressWarnings("unchecked")
    private void applySnapshot(Map<String, Object> p) {
        view = p;
        tell.observe(p);
        discardMemory.observe(p);
        phase = String.valueOf(p.getOrDefault("phase", phase));
        turnPlayer = string(p.get("turnPlayer"));
        topCard = String.valueOf(p.getOrDefault("topCard", topCard));
        activeShape = String.valueOf(p.getOrDefault("activeShape", activeShape));
        pendingPick = number(p.get("pendingPick"));
        finished = "Results".equals(phase);
        paused = Boolean.TRUE.equals(p.get("paused"));
        Object rawPlayers = p.get("players");
        if (rawPlayers instanceof List<?> list) { players.clear(); list.forEach(x -> players.add(String.valueOf(x))); }
        Object rawHand = p.get("yourHand");
        if (rawHand instanceof List<?> list) { hand.clear(); list.forEach(x -> hand.add(String.valueOf(x))); }
        Object rawRules = p.get("rules");
        if (p.get("handSizes") instanceof Map<?, ?> sizes) handSizes = (Map<String, Object>) sizes;
        if (rawRules instanceof Map<?, ?> map) { rules = new LinkedHashMap<>(); map.forEach((k, v) -> rules.put(String.valueOf(k), v)); }
    }

    @SuppressWarnings("unchecked")
    private void applyEvent(Map<String, Object> envelope) {
        String type = String.valueOf(envelope.get("type"));
        Map<String, Object> d = envelope.get("data") instanceof Map<?, ?> map ? (Map<String, Object>) map : Map.of();
        if ("GAME_STARTED".equals(type)) { phase = "Deal"; discardMemory.reset(); tell.reset(); }
        if ("MARKET_RESHUFFLED".equals(type)) discardMemory.reset();
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
        if (paused || finished) return Optional.empty();
        if (view.get("pendingUndo") instanceof String requester && !requester.isEmpty()) return undoResponse(botId);
        if (tellMode()) {
            if (!tell.active(view, botId)) return Optional.empty();
            var signal = tell.action(view, botId, true);
            if (signal.isPresent()) return signal;
        }
        if (!("Turn".equals(phase) || "Waiting".equals(phase)) || !botId.equals(turnPlayer)) return Optional.empty();
        List<String> legal = legalCards();
        if (legal.isEmpty()) return Optional.of(PlayerAction.of(botId, "DRAW", Map.of()));
        String card = legal.get(RNG.nextInt(legal.size()));
        Map<String, Object> data = new LinkedHashMap<>(); data.put("card", card);
        if (card.startsWith("whot-")) data.put("shape", bestShape());
        return Optional.of(PlayerAction.of(botId, "PLAY", data));
    }

    @Override public Optional<PlayerAction> decideLocally(String botId, Difficulty level) {
        if (paused || finished) return Optional.empty();
        if (view.get("pendingUndo") instanceof String requester && !requester.isEmpty()) return undoResponse(botId);
        if (tellMode()) {
            if (!tell.active(view, botId)) return Optional.empty();
            var signal = tell.action(view, botId, true);
            if (signal.isPresent()) return signal;
        }
        if (!("Turn".equals(phase) || "Waiting".equals(phase)) || !botId.equals(turnPlayer)) return Optional.empty();
        List<String> legal = legalCards();
        if (legal.isEmpty()) return Optional.of(PlayerAction.of(botId, "DRAW", Map.of()));
        if (level != Difficulty.EASY) {
            List<String> known = discardMemory.knownCards(level == Difficulty.MEDIUM ? 12 : 0);
            var observation = WhotMonteCarloSearch.Observation.fromView(view, known, botId);
            if (observation.isPresent()) {
                var limits = level == Difficulty.HARD ? new WhotMonteCarloSearch.Limits(32, 24, 16000, 250)
                        : new WhotMonteCarloSearch.Limits(8, 12, 4000, 100);
                var decision = WhotMonteCarloSearch.choose(observation.get(), botId, limits, RNG);
                if (decision.action().isPresent()) return decision.action();
            }
        }
        String card = BotChoices.choose(legal, level, c -> cardScore(c, botId));
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("card", card);
        if (card.startsWith("whot-")) data.put("shape", bestShape());
        return Optional.of(PlayerAction.of(botId, "PLAY", data));
    }

    private double cardScore(String card, String botId) {
        if (hand.size() == 1) return 1000;
        String[] parts = card.split("-", 2);
        int value = Integer.parseInt(parts[1]);
        boolean wild = parts[0].equals("whot");
        double continuity = (hand.stream()
                .filter(other -> other.startsWith(parts[0] + "-") || other.endsWith("-" + value)).count() - 1) * 8;
        double special = (value == 2 && on("pickTwo")) || (value == 14 && on("generalMarket")) ? 20
                : (value == 1 && on("holdOn")) || (value == 8 && on("suspension")) ? 15 : 0;
        boolean opponentClose = handSizes.entrySet().stream()
                .anyMatch(e -> !e.getKey().equals(botId) && (!tellMode()
                        || WhotTellBotStrategy.team(view, e.getKey()) != WhotTellBotStrategy.team(view, botId))
                        && number(e.getValue()) <= 2);
        double score = continuity + special * (opponentClose ? 2 : 1) + (wild ? -25 : value * .2);
        if (tellMode()) {
            List<String> after = new ArrayList<>(hand); after.remove(card);
            int minimum = rules.get("tellMinCards") instanceof Number n ? n.intValue() : 3;
            String rule = String.valueOf(rules.getOrDefault("tellRule", "either"));
            if (after.size() >= minimum) {
                boolean sameShape = after.stream().map(c -> c.split("-")[0]).distinct().count() == 1;
                boolean sameValue = after.stream().map(c -> c.substring(c.lastIndexOf('-') + 1)).distinct().count() == 1;
                if ((sameShape && !"value".equals(rule)) || (sameValue && !"shape".equals(rule))) score += 1000;
            }
            int at = players.indexOf(botId);
            for (int offset = 1; offset < players.size(); offset++) {
                String next = players.get((at + offset) % players.size());
                if (!tell.active(view, next)) continue;
                if (WhotTellBotStrategy.team(view, next) == WhotTellBotStrategy.team(view, botId)) {
                    if (value == 2 && on("pickTwo")) score -= 60;
                    if (value == 8 && on("suspension")) score -= 45;
                }
                break;
            }
        }
        return score;
    }

    private String bestShape() {
        String best = "circle"; int max = -1;
        for (String shape : List.of("circle", "triangle", "cross", "square", "star")) {
            int count = (int) hand.stream().filter(c -> c.startsWith(shape + "-")).count();
            if (count > max) { max = count; best = shape; }
        }
        return best;
    }
    private Optional<PlayerAction> undoResponse(String bot) {
        if (!(view.get("undoResponders") instanceof List<?> voters) || !voters.contains(bot)
                || (view.get("undoAccepted") instanceof java.util.Collection<?> accepted && accepted.contains(bot))) return Optional.empty();
        return Optional.of(PlayerAction.of(bot, "ACCEPT_UNDO", Map.of()));
    }

    private boolean tellMode() { return "tell".equals(view.get("mode")); }
    private boolean on(String key) { return Boolean.TRUE.equals(rules.get(key)); }
    private static int number(Object x) { return x instanceof Number n ? n.intValue() : 0; }
    private static String string(Object x) { return x == null ? null : String.valueOf(x); }
}
