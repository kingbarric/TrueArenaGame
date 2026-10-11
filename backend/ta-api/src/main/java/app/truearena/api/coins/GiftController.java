package app.truearena.api.coins;

import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.push.PushNotificationService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.transaction.reactive.TransactionalOperator;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.Map;
import java.util.UUID;

/**
 * "Gift a coin" from someone's card in a Huud: a fixed {@value #GIFT} coins
 * from your balance to theirs, in one transaction. A gift moves coins but
 * doesn't count toward the receiver's lifetime coins (their tier), so
 * friends can't farm each other's tiers. The receiver hears about it at once
 * — a small splash in the corner of whatever they're doing — or by push.
 */
@RestController
@RequestMapping("/api/v1/players")
public class GiftController {

    public static final int GIFT = 3;
    static final String SENT = "gift_sent";
    static final String RECEIVED = "gift_received";

    private final DatabaseClient db;
    private final TransactionalOperator tx;
    private final InboxRegistry inbox;
    private final ObjectProvider<PushNotificationService> push;

    public GiftController(DatabaseClient db, TransactionalOperator tx, InboxRegistry inbox,
                          ObjectProvider<PushNotificationService> push) {
        this.db = db;
        this.tx = tx;
        this.inbox = inbox;
        this.push = push;
    }

    public record GiftView(int coins, long balance) {
    }

    @PostMapping("/{userId}/gift")
    @Operation(summary = "Gift a player 3 of your coins")
    public Mono<GiftView> gift(@PathVariable UUID userId) {
        return CurrentUser.id().flatMap(me -> give(me, userId));
    }

    public Mono<GiftView> give(UUID from, UUID to) {
        if (from.equals(to)) return Mono.error(ApiExceptions.badRequest("You can't gift yourself"));
        Mono<Map<String, Object>> receiver = db.sql("SELECT u.is_bot, u.is_guest, "
                        + "(SELECT display_name FROM users WHERE id = :from) AS from_name, "
                        + "(SELECT username FROM users WHERE id = :from) AS from_username, "
                        + "EXISTS(SELECT 1 FROM player_blocks b WHERE (b.blocker_id = :from AND b.blocked_id = :to) "
                        + "    OR (b.blocker_id = :to AND b.blocked_id = :from)) AS blocked "
                        + "FROM users u WHERE u.id = :to")
                .bind("from", from).bind("to", to).fetch().one()
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("player not found")));
        return receiver.flatMap(r -> {
            if (Boolean.TRUE.equals(r.get("is_bot")) || Boolean.TRUE.equals(r.get("is_guest"))) {
                return Mono.error(ApiExceptions.badRequest("Gifts are for players with an account"));
            }
            if (Boolean.TRUE.equals(r.get("blocked"))) {
                return Mono.error(ApiExceptions.forbidden("You can't gift this player"));
            }
            String fromName = r.get("from_username") instanceof String u && !u.isBlank() ? u
                    : String.valueOf(r.get("from_name"));
            Mono<Long> move = move(from, -GIFT, SENT, to)
                    .switchIfEmpty(Mono.error(ApiExceptions.conflict("You need " + GIFT + " coins to send a gift")))
                    .flatMap(balance -> move(to, GIFT, RECEIVED, from).thenReturn(balance));
            return tx.transactional(move)
                    .doOnSuccess(balance -> tell(to, from, fromName))
                    .map(balance -> new GiftView(GIFT, balance));
        });
    }

    /** One side of the gift: balance and ledger. Never touches lifetime coins. */
    private Mono<Long> move(UUID user, int delta, String reason, UUID other) {
        return db.sql("UPDATE users SET coins = coins + :delta WHERE id = :id AND coins + :delta >= 0 RETURNING coins")
                .bind("delta", delta).bind("id", user)
                .map((row, meta) -> row.get("coins", Long.class)).one()
                .flatMap(balance -> db.sql("INSERT INTO coin_transactions (user_id, delta, balance_after, reason, ref_id) "
                                + "VALUES (:id, :delta, :balance, :reason, :ref)")
                        .bind("id", user).bind("delta", delta).bind("balance", balance)
                        .bind("reason", reason).bind("ref", other)
                        .fetch().rowsUpdated().thenReturn(balance));
    }

    private void tell(UUID to, UUID from, String fromName) {
        inbox.notify(to, Map.of("type", "COIN_GIFT",
                "data", Map.of("from", from.toString(), "fromName", fromName, "coins", GIFT)));
        PushNotificationService pusher = push.getIfAvailable();
        if (pusher != null) {
            pusher.sendToUserIfOffline(to, "🎁 A gift!", fromName + " sent you " + GIFT + " coins",
                    Map.of("type", "COIN_GIFT"));
        }
    }
}
