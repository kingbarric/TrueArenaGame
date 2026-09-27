package app.truearena.api.bot;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ThreadLocalRandom;

/**
 * The short, in-character things a Cyber Agent says around its own moves —
 * "hm, didn't see that", "right, I'm in trouble now". Written by the model,
 * not picked from a list: a fixed pool of lines gives itself away in about
 * three turns, which is exactly the "repetitive predictive chat" this is
 * meant not to be.
 *
 * <p>Three rules keep it from becoming noise:
 *
 * <ol>
 *   <li><b>It doesn't talk every turn.</b> A running commentary is
 *       exhausting; silence is most of what makes the occasional line land.
 *       See {@link #shouldSpeak}.</li>
 *   <li><b>It can't repeat itself.</b> Recent lines are fed back into the
 *       prompt as an explicit "you already said these" ban list, and an
 *       exact repeat is dropped outright.</li>
 *   <li><b>It reacts to something specific.</b> The prompt carries what just
 *       happened, so the line is about this move rather than generic
 *       filler.</li>
 * </ol>
 *
 * Not thread-safe on its own; one instance lives per {@link BotRuntime},
 * which only touches it from its own socket's frame handling.
 */
final class AgentBanter {

    /** How many past lines to show the model as "don't say these again". */
    private static final int MEMORY = 6;

    /** Hard cap — anything longer stops being a quip and starts being a monologue. */
    private static final int MAX_CHARS = 90;

    private final Deque<String> recent = new ArrayDeque<>();
    private int turnsSinceSpoke = 0;

    /**
     * Whether to say anything at all. Silence is the default and needs no
     * justification — people don't narrate every quiet move, and an agent
     * that comments on each one stops sounding like a person within about
     * three turns.
     *
     * <p>So the two cases are shaped very differently:
     *
     * <ul>
     *   <li><b>Something actually happened</b> (a capture, a swing, the end
     *       of the game): usually worth a word, and a little more likely if
     *       it's been quiet for a while.</li>
     *   <li><b>A routine move</b>: mostly nothing. There's a small nudge for
     *       a long silence so it doesn't go mute for an entire game, but it
     *       is deliberately capped low — a boring game *should* be a quiet
     *       one, and this must never build up to a near-certain comment.</li>
     * </ul>
     */
    boolean shouldSpeak(boolean notable) {
        turnsSinceSpoke++;
        int chance;
        if (notable) {
            chance = 55 + Math.min(20, turnsSinceSpoke * 5);
        } else {
            // Nothing interesting: quiet by default. Tops out around 1-in-5
            // even after a long silence, so stretches of no chat are normal.
            chance = 7 + Math.min(12, turnsSinceSpoke * 2);
        }
        return ThreadLocalRandom.current().nextInt(100) < chance;
    }

    String systemPrompt(String agentName, String gameName, Difficulty difficulty) {
        String temperament = switch (difficulty) {
            case EASY -> "cheerful and a bit clueless; you find your own mistakes funny";
            case MEDIUM -> "relaxed and chatty, like a friend playing on the sofa";
            case HARD -> "dry, confident, lightly smug — never cruel";
        };
        return """
                You are %s, playing %s against a human. You are %s.

                Say ONE short line of table talk reacting to what just happened.

                Hard rules:
                - Under 12 words. One sentence. No emoji, no quotes, no name prefix.
                - Sound like speech, not narration. Contractions, fragments, filler \
                ("hm", "okay", "right") are good.
                - React to the SPECIFIC thing described, not the game in general.
                - Never repeat or reword anything in the "already said" list.
                - Never explain the rules, never give the human advice, never \
                announce your move in notation.
                - If nothing interesting happened, say something small and human \
                rather than something dramatic.
                Reply with the line only.
                """.formatted(agentName, gameName, temperament);
    }

    String userPrompt(String situation) {
        StringBuilder sb = new StringBuilder("What just happened: ").append(situation);
        if (!recent.isEmpty()) {
            sb.append("\n\nAlready said (do not repeat or rephrase any of these):");
            for (String line : recent) {
                sb.append("\n- ").append(line);
            }
        }
        return sb.toString();
    }

    /**
     * Cleans the model's reply into something speakable, or returns null if
     * it isn't usable — empty, too long, or a repeat. Returning null is a
     * normal outcome: saying nothing is always better than saying something
     * that gives the trick away.
     */
    String accept(String raw) {
        if (raw == null) {
            return null;
        }
        String line = raw.trim()
                .replaceAll("^[\"'`]+|[\"'`]+$", "")   // stray quoting around the line
                .replaceAll("^\\s*\\w+\\s*:\\s*", "")  // a "Name:" prefix it wasn't asked for
                .replaceAll("\\s+", " ")
                .trim();
        if (line.isEmpty() || line.length() > MAX_CHARS) {
            return null;
        }
        if (line.lines().count() > 1) {
            return null;
        }
        String key = line.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9 ]", "");
        for (String prior : recent) {
            if (prior.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9 ]", "").equals(key)) {
                return null; // exact repeat slipped through despite the ban list
            }
        }
        remember(line);
        turnsSinceSpoke = 0;
        return line;
    }

    private void remember(String line) {
        recent.addLast(line);
        while (recent.size() > MEMORY) {
            recent.removeFirst();
        }
    }

    List<String> recentLines() {
        return List.copyOf(recent);
    }
}
