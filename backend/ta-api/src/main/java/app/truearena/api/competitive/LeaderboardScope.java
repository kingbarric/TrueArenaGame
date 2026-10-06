package app.truearena.api.competitive;

import java.util.Locale;

/**
 * The boards one rating can appear on. Location decides membership of the
 * scoped ones; it never produces a second rating.
 */
public enum LeaderboardScope {
    GLOBAL, COUNTRY, REGION, FRIENDS;

    public static LeaderboardScope parse(String raw) {
        if (raw == null || raw.isBlank()) return GLOBAL;
        return switch (raw.trim().toLowerCase(Locale.ROOT)) {
            case "country", "national" -> COUNTRY;
            case "region", "state" -> REGION;
            case "friends" -> FRIENDS;
            default -> GLOBAL;
        };
    }

    public String wire() {
        return name().toLowerCase(Locale.ROOT);
    }
}
