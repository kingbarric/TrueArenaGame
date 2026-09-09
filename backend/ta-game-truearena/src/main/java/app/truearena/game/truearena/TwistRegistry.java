package app.truearena.game.truearena;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Catalog version 1 (docs/GAME_CONFIG.md §5). Every twist id is registered with its
 * display metadata and default params so the config validator can check references and
 * the lobby can render toggles. Behavioural hooks land incrementally; {@code hidden_legacy}
 * is wired through {@link TrueArenaModule}.
 */
public final class TwistRegistry {

    public record Twist(String id, String name, String summary, List<String> hooks, Map<String, Object> defaults) {
    }

    private static final Map<String, Twist> BY_ID = new LinkedHashMap<>();

    private static void add(String id, String name, String summary, List<String> hooks, Map<String, Object> defaults) {
        BY_ID.put(id, new Twist(id, name, summary, hooks, defaults));
    }

    static {
        add("hidden_legacy", "Hidden Legacy",
                "If the last original Traitor falls before the trigger, one living Faithful is secretly recruited.",
                List.of("WinCheck", "Results"), Map.of("trigger", "before_round_3"));
        add("poisoned_gift", "Poisoned Gift & the Shield",
                "Traitors pick Direct Poison (a delayed death) or plant a public mystery Shield.",
                List.of("Night", "MorningReveal", "Elimination"),
                Map.of("uses", 1, "announceClaim", true, "hideClaimant", true));
        add("secret_accusation", "Secret Accusation",
                "One Faithful holds a one-use public accusation; the accused gets 60s to answer.",
                List.of("RoundTable", "Vote"), Map.of("defenseSeconds", 60));
        add("blackmail", "Blackmail",
                "One Faithful privately learns one random player's true side.",
                List.of("RoleReveal"), Map.of());
        add("double_agent", "Double Agent",
                "One Faithful is flagged recruitable for a later night.",
                List.of("Night"), Map.of());
        add("last_will", "Last Will",
                "An eliminated player may leave one host-approved final sentence.",
                List.of("MorningReveal", "Elimination"), Map.of("maxChars", 140));
        add("confessional", "Confessional",
                "Once a round every living player submits one line, revealed anonymously.",
                List.of("RoundTable"), Map.of("perRound", 1));
        add("immunity_coin", "Immunity Coin",
                "A challenge winner holds a public one-use immunity from elimination.",
                List.of("Elimination"), Map.of());
        add("silent_witness", "Silent Witness",
                "One Faithful learns a murdered player was definitely Faithful.",
                List.of("MorningReveal"), Map.of());
        add("false_reveal", "False Reveal",
                "Once a game the Traitors can force an eliminated Faithful's role to read unknown.",
                List.of("MorningReveal", "Elimination"), Map.of("uses", 1));
        add("trial_of_two", "Trial of Two",
                "On a tie, both tied players get 45s to defend, then a final vote.",
                List.of("Vote"), Map.of("defenseSeconds", 45));
        add("survivors_choice", "Survivors' Choice",
                "At the final four the group may end early; any Traitor alive means the Traitors win.",
                List.of("WinCheck"), Map.of());
    }

    private TwistRegistry() {
    }

    public static boolean isKnown(String id) {
        return BY_ID.containsKey(id);
    }

    public static Map<String, Twist> all() {
        return Map.copyOf(BY_ID);
    }

    public static Twist get(String id) {
        return BY_ID.get(id);
    }

    /** hidden_legacy: enabled, not yet triggered, and the trigger condition holds. */
    static boolean recruitEligible(TruearenaState.Draft d) {
        if (d.recruitDone || !d.config.twistEnabled("hidden_legacy")) {
            return false;
        }
        Map<String, Object> p = d.config.twistParams("hidden_legacy");
        Object trigger = p.getOrDefault("trigger", "before_round_3");
        if (trigger instanceof Map<?, ?> m && m.get("beforeRound") instanceof Number n) {
            return d.round < n.intValue();
        }
        return switch (String.valueOf(trigger)) {
            case "while_players_above_5" -> d.alive.size() > 5;
            default -> d.round < 3; // before_round_3
        };
    }
}
