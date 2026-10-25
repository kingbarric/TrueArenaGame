package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;

import java.security.SecureRandom;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/** Signal decisions use only this player's private view and public table information. */
final class WhotTellBotStrategy {
    private static final List<String> SYMBOLS = List.of("🪐", "🔮", "🛸", "🧿", "🗝️", "🌙", "✨", "🧩");
    private static final SecureRandom RANDOM = new SecureRandom();
    private String previousPhase = "", proposal = SYMBOLS.get(RANDOM.nextInt(SYMBOLS.size()));
    private String signalledHand;
    private long buzzed = -1;

    void reset() {
        previousPhase = ""; signalledHand = null; buzzed = -1;
        proposal = SYMBOLS.get(RANDOM.nextInt(SYMBOLS.size()));
    }

    void observe(Map<String, Object> view) {
        String phase = String.valueOf(view.get("phase"));
        if ("Signals".equals(phase) && !phase.equals(previousPhase)) reset();
        previousPhase = phase;
    }

    boolean active(Map<String, Object> view, String bot) {
        int team = team(view, bot);
        return team >= 0 && !numbers(view.get("qualifiedTeams")).contains(team)
                && !numbers(view.get("eliminatedTeams")).contains(team);
    }

    Optional<PlayerAction> action(Map<String, Object> view, String bot, boolean commit) {
        if (!active(view, bot)) return Optional.empty();
        List<String> pair = teams(view).get(team(view, bot));
        String symbol = String.valueOf(view.getOrDefault("yourSignal", ""));
        if ("Signals".equals(view.get("phase"))) {
            if (Boolean.TRUE.equals(view.get("yourSignalConfirmed"))) return Optional.empty();
            // One proposer per pair prevents two agents overwriting each other's choices.
            if (symbol.isEmpty() && !pair.getFirst().equals(bot)) return Optional.empty();
            return Optional.of(PlayerAction.of(bot, "CHOOSE_SIGNAL", Map.of("symbol", symbol.isEmpty() ? proposal : symbol)));
        }
        if (!List.of("Turn", "Waiting").contains(view.get("phase"))) return Optional.empty();
        Map<?, ?> rules = view.get("rules") instanceof Map<?, ?> r ? r : Map.of();
        int minimum = rules.get("tellMinCards") instanceof Number n ? n.intValue() : 3;
        Map<?, ?> signal = view.get("signal") instanceof Map<?, ?> s ? s : Map.of();
        long age = signal.get("sentAtMs") instanceof Number n ? System.currentTimeMillis() - n.longValue() : Long.MAX_VALUE;
        boolean live = age >= 0 && age < 2500;
        if (live && signal.get("id") instanceof Number id && id.longValue() != buzzed
                && pair.contains(signal.get("by")) && !bot.equals(signal.get("by"))
                && !symbol.isEmpty() && symbol.equals(signal.get("symbol"))) {
            Map<?, ?> sizes = view.get("handSizes") instanceof Map<?, ?> s ? s : Map.of();
            if (sizes.get(signal.get("by")) instanceof Number count && count.intValue() >= minimum) {
                if (commit) buzzed = id.longValue();
                return Optional.of(PlayerAction.of(bot, "BUZZ", Map.of("signalId", id.longValue())));
            }
        }
        List<String> hand = view.get("yourHand") instanceof List<?> h ? h.stream().map(String::valueOf).toList() : List.of();
        String key = hand.stream().sorted().toList().toString();
        if (!symbol.isEmpty() && !live && !key.equals(signalledHand) && hand.size() >= minimum) {
            boolean shape = hand.stream().map(c -> c.split("-")[0]).distinct().count() == 1;
            boolean value = hand.stream().map(c -> c.substring(c.lastIndexOf('-') + 1)).distinct().count() == 1;
            String rule = rules.get("tellRule") instanceof String name ? name : "either";
            if ((shape && !"value".equals(rule)) || (value && !"shape".equals(rule))) {
                if (commit) signalledHand = key;
                return Optional.of(PlayerAction.of(bot, "SIGNAL", Map.of("symbol", symbol)));
            }
        }
        return Optional.empty();
    }

    static int team(Map<String, Object> view, String player) {
        List<List<String>> teams = teams(view);
        for (int i = 0; i < teams.size(); i++) if (teams.get(i).contains(player)) return i;
        return -1;
    }

    static List<List<String>> teams(Map<String, Object> view) {
        return view.get("teams") instanceof List<?> list ? list.stream().filter(List.class::isInstance)
                .map(p -> ((List<?>) p).stream().map(String::valueOf).toList()).toList() : List.of();
    }

    private static List<Integer> numbers(Object value) {
        return value instanceof List<?> list ? list.stream().filter(Number.class::isInstance)
                .map(n -> ((Number) n).intValue()).toList() : List.of();
    }
}
