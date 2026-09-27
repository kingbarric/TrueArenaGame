package app.truearena.api.bot;

/**
 * Amateur/Pro/Legend from the player's perspective — Easy/Medium/Hard in
 * code. What actually changes per level is entirely up to the
 * {@link LlmMovePicker} implementation (a cheaper model and a bare prompt
 * for Easy, the strongest model and a fuller strategic prompt for Hard) —
 * nothing here dictates that, it's just the label threaded through.
 */
public enum Difficulty {
    EASY, MEDIUM, HARD;

    public static Difficulty parse(String raw) {
        if (raw == null || raw.isBlank()) {
            return MEDIUM;
        }
        try {
            return valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            return MEDIUM;
        }
    }
}
