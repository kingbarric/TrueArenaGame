package app.truearena.engine;

import java.util.List;
import java.util.Map;

/**
 * The whole rule surface of the Traitors-and-Faithful engine as data. Closed value
 * sets are kept as validated strings (see {@link ConfigVocab}) so this record binds
 * cleanly from JSON and the module stays framework-free. Full model: docs/GAME_CONFIG.md.
 */
public record GameConfig(
        int catalogVersion,
        String preset,
        Table table,
        Timers timers,
        NightKill nightKill,
        String revealOnElimination,   // always | never | alternating
        String tieBreak,              // revote | no_elimination | random | sudden_death | host_decides | trial_of_two
        String secondTie,             // no_elimination | random | host_decides
        int suddenDeathSeconds,
        String afk,                   // abstain | host_assigns
        String voteReveal,            // sequential | all_at_once
        String endgameVeil,           // final_4 | final_5 | final_6 | off
        Map<String, Map<String, Object>> twists
) {

    public GameConfig {
        if (twists == null) {
            twists = Map.of();
        }
    }

    public boolean twistEnabled(String id) {
        return twists.containsKey(id);
    }

    public Map<String, Object> twistParams(String id) {
        return twists.getOrDefault(id, Map.of());
    }

    /** Living-player count at which the Veiled Endgame turns on. 0 = never. */
    public int veilThreshold() {
        return switch (endgameVeil == null ? "off" : endgameVeil) {
            case "final_4" -> 4;
            case "final_5" -> 5;
            case "final_6" -> 6;
            default -> 0;
        };
    }

    public record Table(
            int players,
            int minPlayers,
            int maxPlayers,
            boolean adminOverride,
            List<List<Integer>> traitorCurve
    ) {
        /** Resolve the traitor count for an actual player count from the ascending curve. */
        public int resolveTraitors(int playerCount) {
            int t = 1;
            for (List<Integer> pair : traitorCurve) {
                if (playerCount >= pair.get(0)) {
                    t = pair.get(1);
                }
            }
            return t;
        }
    }

    public record Timers(int night, int roundTable, int vote, int defense) {
    }

    public record NightKill(
            String openingNight,          // on | off
            Integer doubleAfterRound,     // round R → doubles allowed after R; null/0 = never
            boolean allowSkip,
            boolean requireTraitorConsensus
    ) {
        public boolean opensWithKill() {
            return !"off".equalsIgnoreCase(openingNight);
        }
    }
}
