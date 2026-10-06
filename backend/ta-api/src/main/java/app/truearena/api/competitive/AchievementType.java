package app.truearena.api.competitive;

/**
 * The achievement catalog. Lives in code rather than a table so a new badge
 * needs no migration and can't drift from the rule that awards it; the
 * per-player fact is a {@code player_achievements} row keyed by {@link #name()}.
 *
 * <p>{@code displayPriority} orders a profile's badge shelf (highest first);
 * {@code rarity} is the presentation weight. Founding tiers are listed here so
 * they render through the same path, but are never stored — they are derived
 * from the PlayHuud number.
 */
public enum AchievementType {
    FOUNDING_100("Founding 100", "👑", 1000, "legendary", false),
    FOUNDING_1000("Founding 1,000", "💎", 900, "epic", false),
    FOUNDING_10000("Founding 10,000", "⭐", 800, "rare", false),

    DEFEATED_NO_1("Defeated the #1 Player", "🥇", 700, "legendary", true),
    DEFEATED_TOP_10("Defeated a Top-10 Player", "⚔️", 600, "epic", true),
    DEFEATED_TOP_100("Defeated a Top-100 Player", "🗡️", 500, "rare", true),

    STREAK_25("25 Match Win Streak", "🔥", 450, "epic", true),
    STREAK_10("10 Match Win Streak", "🔥", 400, "rare", true),

    WINS_1000("1,000 Ranked Wins", "🏛️", 350, "legendary", true),
    WINS_100("100 Ranked Wins", "🎖️", 300, "rare", true),
    WINS_10("10 Ranked Wins", "🏅", 200, "uncommon", true),
    FIRST_RANKED_WIN("First Ranked Win", "✅", 100, "common", true);

    private final String label;
    private final String icon;
    private final int displayPriority;
    private final String rarity;
    private final boolean perGame;

    AchievementType(String label, String icon, int displayPriority, String rarity, boolean perGame) {
        this.label = label;
        this.icon = icon;
        this.displayPriority = displayPriority;
        this.rarity = rarity;
        this.perGame = perGame;
    }

    public String label() {
        return label;
    }

    public String icon() {
        return icon;
    }

    public int displayPriority() {
        return displayPriority;
    }

    public String rarity() {
        return rarity;
    }

    /** Earned per game type (stored with {@code game_type}) rather than once per account. */
    public boolean perGame() {
        return perGame;
    }

    public static AchievementType founding(FoundingTier tier) {
        if (tier == null) {
            return null;
        }
        return switch (tier) {
            case FOUNDING_100 -> FOUNDING_100;
            case FOUNDING_1000 -> FOUNDING_1000;
            case FOUNDING_10000 -> FOUNDING_10000;
        };
    }

    /** Lenient lookup for stored rows — an achievement retired from the catalog is skipped, not an error. */
    public static AchievementType parse(String raw) {
        try {
            return raw == null ? null : valueOf(raw);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }
}
