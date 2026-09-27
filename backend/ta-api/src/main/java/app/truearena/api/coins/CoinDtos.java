package app.truearena.api.coins;

import java.time.Instant;
import java.util.List;

public final class CoinDtos {

    private CoinDtos() {
    }

    public record WalletTransactionView(long delta, long balanceAfter, String reason, Instant createdAt) {
    }

    /**
     * {@code nextTier}/{@code coinsToNextTier} are null at {@code Legend} —
     * nothing further to reach. {@code tierProgress} is 0..1 within the
     * current tier's band, for a progress bar.
     */
    public record TierView(String tier, long lifetimeCoins, String nextTier, Long coinsToNextTier, double tierProgress) {
        public static TierView of(CoinTier tier, long lifetimeCoins) {
            CoinTier next = tier.next();
            double progress = 1.0;
            Long coinsToNext = null;
            if (next != null) {
                long span = next.minLifetimeCoins - tier.minLifetimeCoins;
                long into = lifetimeCoins - tier.minLifetimeCoins;
                progress = span > 0 ? Math.min(1.0, (double) into / span) : 1.0;
                coinsToNext = Math.max(0, next.minLifetimeCoins - lifetimeCoins);
            }
            return new TierView(tier.label, lifetimeCoins, next == null ? null : next.label, coinsToNext, progress);
        }
    }

    public record WalletView(long balance, TierView tier, List<WalletTransactionView> recent) {
    }
}
