package app.truearena.api.bot;

/**
 * Rookie/Pro/Legend in the app; Easy/Medium/Hard on the wire. Local game
 * strategies set their own evaluation, search budgets and legal randomness.
 * Optional communication may also vary by level. These are not rated strengths.
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
