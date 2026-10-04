package app.truearena.api.coins;

import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.CoinTransactionRepository;
import app.truearena.persistence.CoinTransactionRow;
import app.truearena.persistence.UserRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

/**
 * The coin ledger — free/earned only, no real-money purchase and no cash-out
 * anywhere in this app, so no payment integration and no gambling-law
 * surface even though match stakes let players wager it (coins in, coins
 * out, never real money either direction). Every balance change is atomic
 * at the DB level ({@code UserRepository#adjustCoins}, a single conditional
 * UPDATE...RETURNING) and paired with an append-only {@code
 * coin_transactions} row — never just the balance alone.
 *
 * <p>Covers earning (match participation/win rewards, wired into {@code
 * GameOrchestrator.finishGame}) and match-stake escrow/payout/refund (wired
 * into {@code RoomService.create}/{@code join}/{@code abandon} and {@code
 * GameOrchestrator.payoutStake}). Cosmetic-unlock purchases are still the
 * natural next step, not built yet.
 */
@Service
public class CoinService {

    /**
     * What a match pays out.
     *
     * <p>Only a match against another person pays anything at all. Cyber
     * Agents are a free, always-available shared pool now (see
     * {@code BotService}) — if beating or even just finishing against one
     * paid out, grinding the nearest free agent would be a zero-cost, zero-
     * risk coin faucet instead of the point of this ledger, which is to get
     * people playing each other. {@code GameOrchestrator.awardCoins} is where
     * this is enforced — a human opponent is required for any payout.
     *
     * <p>Losing never costs coins. The balance is earned-only and can't be
     * bought, so a player who runs dry has no way back in — and being unable
     * to afford an opponent because you lost to one is exactly the wrong
     * place for that wall to be.
     */
    public static final long WIN_VS_PERSON = 30;
    public static final long LOSS_VS_PERSON = 10;
    public static final long TIE_VS_PERSON = 15;

    public static final String REASON_MATCH_WIN = "match_win";
    public static final String REASON_MATCH_LOSS = "match_loss";
    public static final String REASON_MATCH_TIE = "match_tie";
    public static final String REASON_WELCOME = "welcome_grant";

    /** What a brand-new account starts with, enough to join a small staked game. */
    public static final long WELCOME_GRANT = 120;
    public static final String REASON_MATCH_STAKE_ESCROW = "match_stake_escrow";
    public static final String REASON_MATCH_STAKE_PAYOUT = "match_stake_payout";
    public static final String REASON_MATCH_STAKE_REFUND = "match_stake_refund";

    private final UserRepository users;
    private final CoinTransactionRepository ledger;

    public CoinService(UserRepository users, CoinTransactionRepository ledger) {
        this.users = users;
        this.ledger = ledger;
    }

    public Mono<Long> balance(UUID userId) {
        return users.coinsOf(userId).defaultIfEmpty(0L);
    }

    public Mono<Long> lifetimeCoins(UUID userId) {
        return users.lifetimeCoinsOf(userId).defaultIfEmpty(0L);
    }

    public Mono<CoinTier> tier(UUID userId) {
        return lifetimeCoins(userId).map(CoinTier::forLifetimeCoins);
    }

    public Mono<Long> credit(UUID userId, long amount, String reason, UUID refId) {
        if (amount <= 0) {
            return Mono.error(ApiExceptions.badRequest("credit amount must be positive"));
        }
        return adjust(userId, amount, reason, refId);
    }

    public Mono<Long> debit(UUID userId, long amount, String reason, UUID refId) {
        if (amount <= 0) {
            return Mono.error(ApiExceptions.badRequest("debit amount must be positive"));
        }
        return adjust(userId, -amount, reason, refId)
                .switchIfEmpty(Mono.error(ApiExceptions.conflict("not enough coins")));
    }

    private Mono<Long> adjust(UUID userId, long delta, String reason, UUID refId) {
        return users.adjustCoins(userId, delta)
                .flatMap(newBalance -> ledger.save(CoinTransactionRow.of(userId, delta, newBalance, reason, refId))
                        .thenReturn(newBalance));
    }

    public Flux<CoinTransactionRow> history(UUID userId, int limit) {
        int bounded = Math.min(Math.max(limit, 1), 100);
        return ledger.findByUserIdOrderByCreatedAtDesc(userId, PageRequest.of(0, bounded));
    }
}
