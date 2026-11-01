package app.truearena.api.bot;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.random.RandomGenerator;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * What a Cyber Agent is called at the table: cyber_max, cyber_kim — never
 * "Cyber 1" or "Cyber Agent 2". A name the host typed is kept; the old
 * numbered defaults, which older apps still send, get a fresh name instead.
 */
final class AgentNames {

    static final List<String> NAMES = List.of(
            "max", "tan", "kim", "zed", "ivy", "rex", "jax", "kai", "lux", "ace",
            "dex", "neo", "sky", "ray", "leo", "mia", "nia", "obi", "ama", "kofi",
            "zola", "tobi", "femi", "ike", "yaw", "esi", "sol", "pip", "jin", "lia",
            "fox", "jet", "kit", "ren", "vic", "zia", "nova", "remi", "tayo", "kemi");

    /** "Cyber", "Cyber 3", "Cyber Agent", "cyber_agent1" — the numbered names this replaces. */
    private static final Pattern OLD_DEFAULT = Pattern.compile("(?i)cyber[ _]*(agent)?[ _]*\\d*");

    private AgentNames() {
    }

    static boolean needsName(String requested) {
        return requested == null || requested.isBlank() || OLD_DEFAULT.matcher(requested.trim()).matches();
    }

    /** A cyber_ name nobody at this table already goes by. */
    static String pick(Collection<String> taken, RandomGenerator random) {
        Set<String> used = taken.stream().filter(n -> n != null)
                .map(n -> n.trim().toLowerCase(Locale.ROOT)).collect(Collectors.toSet());
        List<String> free = new ArrayList<>();
        for (String n : NAMES) if (!used.contains("cyber_" + n)) free.add("cyber_" + n);
        if (!free.isEmpty()) return free.get(random.nextInt(free.size()));
        for (int i = 2; ; i++) {
            String n = "cyber_" + NAMES.get(random.nextInt(NAMES.size())) + i;
            if (!used.contains(n)) return n;
        }
    }
}
