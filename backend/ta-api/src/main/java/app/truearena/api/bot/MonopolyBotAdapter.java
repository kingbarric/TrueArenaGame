package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.*;

/** The agent sees its player snapshot, and can choose only engine-validated actions. */
public final class MonopolyBotAdapter implements GameBotAdapter {
    private static final ObjectMapper JSON = new ObjectMapper();
    private List<Map<String, Object>> choices = List.of();
    private Map<String, Object> state = Map.of();
    private Difficulty level = Difficulty.MEDIUM;
    private String actor;

    @Override public String gameType() { return "monopoly"; }

    @Override public Optional<BotPrompt> onFrame(String type, Map<String, Object> payload,
                                                String botId, Difficulty difficulty) {
        if ("EVENT".equals(type) && "GAME_PAUSED".equals(payload.get("type"))) {
            choices = List.of();
            return Optional.empty();
        }
        if (!"SNAPSHOT".equals(type)) return Optional.empty();
        choices = List.of();
        actor = botId;
        state = payload;
        level = difficulty;
        if (Boolean.TRUE.equals(payload.get("paused"))) return Optional.empty();
        if ("Results".equals(payload.get("phase")) || payload.get("winner") != null) return Optional.empty();
        if (!(payload.get("legalActions") instanceof List<?> actions)) return Optional.empty();
        @SuppressWarnings("unchecked") List<Map<String, Object>> legal = (List<Map<String, Object>>) (List<?>) actions;
        choices = legal;
        boolean turn = botId.equals(payload.get("decisionPlayer"));
        if (!turn) choices = choices.stream().filter(c -> Set.of("ACCEPT_TRADE", "DECLINE_TRADE").contains(c.get("action"))).toList();
        if (choices.isEmpty()) return Optional.empty();
        try {
            return Optional.of(new BotPrompt(
                    "You are a Huudpoly Cyber Agent at " + difficulty + " difficulty. Buy useful properties, "
                    + "complete colour groups, build evenly, keep a cash reserve, bid sensibly, resolve debts, "
                    + "and accept only fair trades. Choose exactly one indexed legal action. Reply JSON {\"index\":0}. "
                    + "No invented actions. This is game state only, not social chat.",
                    JSON.writeValueAsString(Map.of("you", botId, "state", payload, "choices", choices))));
        } catch (Exception ignored) { return Optional.empty(); }
    }

    @Override public Optional<PlayerAction> parseAction(String raw, String botId) {
        if (!botId.equals(actor)) return Optional.empty();
        try {
            Object index = JSON.readValue(raw, Map.class).get("index");
            if (index instanceof Number n && n.doubleValue() == n.intValue()
                    && n.intValue() >= 0 && n.intValue() < choices.size()) return Optional.of(action(botId, choices.get(n.intValue())));
        } catch (Exception ignored) { }
        return Optional.empty();
    }

    @Override public Optional<PlayerAction> fallbackAction(String botId) {
        if (!botId.equals(actor)) return Optional.empty();
        return choices.stream().max(Comparator.comparingDouble(this::score)).map(c -> action(botId, c));
    }

    @Override public Optional<PlayerAction> decideLocally(String botId, Difficulty difficulty) {
        if (!botId.equals(actor) || choices.isEmpty()) return Optional.empty();
        level = difficulty;
        // Never randomise forced debt settlement or bankruptcy ahead of a solvent action.
        return Optional.of(action(botId, choices.stream().max(Comparator.comparingDouble(this::score)).orElseThrow()));
    }

    @SuppressWarnings("unchecked")
    private PlayerAction action(String id, Map<String, Object> c) {
        return PlayerAction.of(id, (String) c.get("action"), (Map<String, Object>) c.get("data"));
    }

    private double score(Map<String, Object> c) {
        String kind = (String) c.get("action");
        Map<?, ?> data = map(c.get("data"));
        Map<?, ?> self = map(map(state.get("playerState")).get(actor));
        int cash = number(self.get("cash"));
        int reserve = level == Difficulty.EASY ? 80 : level == Difficulty.HARD ? 220 : 150;
        Map<?, ?> deed = board(number(data.get("property")));
        return switch (kind) {
            case "PAY_DEBT" -> 1000;
            case "BANKRUPT" -> -10000; // Exhaust legal ways to raise cash before conceding.
            case "USE_JAIL_CARD" -> 200;
            case "PAY_JAIL" -> cash >= reserve + 50 ? 150 : 5;
            case "ROLL" -> 100;
            case "BUY" -> cash >= reserve + number(board(number(self.get("position"))).get("price")) ? 150 : 5;
            case "AUCTION" -> 100;
            case "BID" -> {
                Map<?, ?> auction = map(state.get("auction"));
                int value = number(board(number(auction.get("property"))).get("price"));
                int bid = number(data.get("amount"));
                yield bid <= Math.min(cash - reserve, value * (level == Difficulty.HARD ? 1.15 : 0.85)) ? 150 - bid * .01 : 0;
            }
            case "PASS", "END_TURN" -> 50;
            case "BUILD" -> cash >= reserve + number(deed.get("buildingCost")) ? 120 - number(deed.get("price")) * .01 : 0;
            case "UNMORTGAGE" -> cash >= reserve + number(deed.get("price")) * .55 ? 100 : 0;
            case "MORTGAGE" -> "Debt".equals(state.get("phase")) ? 130 - number(deed.get("price")) * .01 : 0;
            case "SELL_BUILDING" -> "Debt".equals(state.get("phase")) ? 120 : 0;
            case "SELL_GROUP" -> "Debt".equals(state.get("phase")) ? 110 : 0;
            case "ACCEPT_TRADE" -> fairTrade(data.get("tradeId")) ? 250 : -1;
            case "DECLINE_TRADE" -> 200;
            default -> -10;
        };
    }

    private boolean fairTrade(Object id) {
        if (!(state.get("tradeOffers") instanceof List<?> offers)) return false;
        for (Object raw : offers) {
            Map<?, ?> t = map(raw);
            if (Objects.equals(t.get("id"), id)) {
                int gain = number(t.get("giveCash")) + value(t.get("giveDeeds"));
                int cost = number(t.get("takeCash")) + value(t.get("takeDeeds"));
                return gain > 0 && gain >= cost * (level == Difficulty.HARD ? 1.1 : 1.0);
            }
        }
        return false;
    }

    private int value(Object raw) {
        if (!(raw instanceof List<?> ids)) return 0;
        int sum = 0;
        for (Object id : ids) {
            int price = number(board(number(id)).get("price"));
            Map<?, ?> owned = map(map(state.get("deeds")).get(String.valueOf(number(id))));
            sum += Boolean.TRUE.equals(owned.get("mortgaged")) ? (int) (price * .45) : price;
        }
        return sum;
    }
    private Map<?, ?> board(int id) {
        if (state.get("board") instanceof List<?> board && id >= 0 && id < board.size()) return map(board.get(id));
        return Map.of();
    }
    private static Map<?, ?> map(Object raw) { return raw instanceof Map<?, ?> m ? m : Map.of(); }
    private static int number(Object raw) { return raw instanceof Number n ? n.intValue() : 0; }
}
