package app.truearena.api.coins;

/**
 * Status ladder over lifetime coins earned (never current balance, so
 * spending coins never demotes you — see {@code V13__coin_tiers.sql}).
 * Naming follows familiar gifting/status-tier conventions (TikTok LIVE
 * levels, common gacha/loyalty ladders) rather than inventing new vocabulary
 * — "Rose" in particular is TikTok's own name for a small low-tier gift.
 */
public enum CoinTier {
    ROOKIE("Rookie", 0),
    RISING_STAR("Rising Star", 250),
    ROSE("Rose", 750),
    BRONZE("Bronze", 1_500),
    SILVER("Silver", 3_000),
    GOLD("Gold", 6_000),
    PLATINUM("Platinum", 12_000),
    DIAMOND("Diamond", 25_000),
    CROWN("Crown", 50_000),
    LEGEND("Legend", 100_000);

    public final String label;
    public final long minLifetimeCoins;

    CoinTier(String label, long minLifetimeCoins) {
        this.label = label;
        this.minLifetimeCoins = minLifetimeCoins;
    }

    public static CoinTier forLifetimeCoins(long lifetimeCoins) {
        CoinTier current = ROOKIE;
        for (CoinTier tier : values()) {
            if (lifetimeCoins >= tier.minLifetimeCoins) {
                current = tier;
            }
        }
        return current;
    }

    /** Null once at the top tier (Legend) — there's nothing further to reach. */
    public CoinTier next() {
        CoinTier[] all = values();
        int i = ordinal();
        return i + 1 < all.length ? all[i + 1] : null;
    }
}
