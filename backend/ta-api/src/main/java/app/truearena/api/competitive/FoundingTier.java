package app.truearena.api.competitive;

/**
 * Early-adopter status, a pure function of the permanent PlayHuud number.
 * Never stored: the number is immutable, so the tier is too, and a stored copy
 * could only ever disagree with it.
 */
public enum FoundingTier {
    FOUNDING_100(100, "Founding 100"),
    FOUNDING_1000(1_000, "Founding 1,000"),
    FOUNDING_10000(10_000, "Founding 10,000");

    private final long upTo;
    private final String label;

    FoundingTier(long upTo, String label) {
        this.upTo = upTo;
        this.label = label;
    }

    public String label() {
        return label;
    }

    /** The tier for a PlayHuud number, or null past #10,000 (and for bots, which have none). */
    public static FoundingTier of(Long playhuudNumber) {
        if (playhuudNumber == null || playhuudNumber < 1) {
            return null;
        }
        for (FoundingTier tier : values()) {
            if (playhuudNumber <= tier.upTo) {
                return tier;
            }
        }
        return null;
    }

    /** {@code 127 -> "#000127"}. Six digits, growing naturally past #999,999. */
    public static String formatNumber(Long playhuudNumber) {
        return playhuudNumber == null ? null : String.format("#%06d", playhuudNumber);
    }
}
