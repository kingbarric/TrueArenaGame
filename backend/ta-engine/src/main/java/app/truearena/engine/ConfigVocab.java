package app.truearena.engine;

import java.util.Set;

/** The closed value sets referenced by {@link GameConfig}. Validation lives in the module. */
public final class ConfigVocab {

    public static final int CATALOG_VERSION = 1;

    public static final Set<String> REVEAL = Set.of("always", "never", "alternating");
    public static final Set<String> TIE_BREAK =
            Set.of("revote", "no_elimination", "random", "sudden_death", "host_decides", "trial_of_two");
    public static final Set<String> SECOND_TIE = Set.of("no_elimination", "random", "host_decides");
    public static final Set<String> AFK = Set.of("abstain", "host_assigns");
    public static final Set<String> VOTE_REVEAL = Set.of("sequential", "all_at_once");
    public static final Set<String> VEIL = Set.of("final_4", "final_5", "final_6", "off");
    public static final Set<String> OPENING_NIGHT = Set.of("on", "off");

    /** Twist ids known to catalog version 1 (docs/GAME_CONFIG.md §5). */
    public static final Set<String> TWISTS = Set.of(
            "hidden_legacy", "poisoned_gift", "secret_accusation", "blackmail", "double_agent",
            "last_will", "confessional", "immunity_coin", "silent_witness", "false_reveal",
            "trial_of_two", "survivors_choice"
    );

    private ConfigVocab() {
    }
}
