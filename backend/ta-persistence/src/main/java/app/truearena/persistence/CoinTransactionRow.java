package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * One line in a user's coin ledger — always paired with the atomic balance
 * update that produced it (see {@code UserRepository#adjustCoins}), never
 * written standalone. {@code balanceAfter} is the real post-transaction
 * balance from that same atomic update, not a separately-read value, so
 * it can't drift from a concurrent transaction landing in between.
 */
@Table("coin_transactions")
public record CoinTransactionRow(
        @Id UUID id,
        @Column("user_id") UUID userId,
        long delta,
        @Column("balance_after") long balanceAfter,
        String reason,
        @Column("ref_id") UUID refId,
        @Column("created_at") Instant createdAt
) {
    public static CoinTransactionRow of(UUID userId, long delta, long balanceAfter, String reason, UUID refId) {
        return new CoinTransactionRow(null, userId, delta, balanceAfter, reason, refId, null);
    }
}
