package app.truearena.persistence;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.Collection;
import java.util.UUID;

public interface UserRepository extends ReactiveCrudRepository<UserRow, UUID> {
    Mono<UserRow> findByPhone(String phone);

    /** Contact-invite matching (see {@code FriendService.matchContacts}) — every user whose phone is in the set. */
    Flux<UserRow> findByPhoneIn(Collection<String> phones);

    Mono<UserRow> findByEmail(String email);

    Mono<UserRow> findByDeviceId(String deviceId);

    Mono<UserRow> findByUsername(String username);

    Mono<Boolean> existsByUsername(String username);

    /**
     * A player's saved Cyber Agents for one game, oldest first — the list
     * behind "add an agent you already made" (see {@code BotService}). An
     * agent is just a bot {@code users} row that remembers who created it,
     * so there's no separate roster table to keep in sync.
     */
    @Query("SELECT * FROM users WHERE is_bot AND owner_user_id = :ownerId AND bot_game_type = :gameType "
            + "ORDER BY created_at")
    Flux<UserRow> findAgentsOf(UUID ownerId, String gameType);

    /** Every agent a player owns, across all games — used to show them in the friends list. */
    @Query("SELECT * FROM users WHERE is_bot AND owner_user_id = :ownerId ORDER BY created_at")
    Flux<UserRow> findAgentsOf(UUID ownerId);

    @Query("SELECT coins FROM users WHERE id = :userId")
    Mono<Long> coinsOf(UUID userId);

    /**
     * Atomically applies {@code delta} to a user's coin balance and returns
     * the resulting balance — a negative {@code delta} (a debit) only
     * applies if the balance would stay non-negative, so this is also how
     * "insufficient funds" gets checked: an empty result means it was
     * refused, not that the user doesn't exist (see {@code CoinService}).
     * One round trip, no read-then-write race — the WHERE clause and the
     * RETURNING value come from the same atomic statement.
     */
    @Query("UPDATE users SET coins = coins + :delta, lifetime_coins = lifetime_coins + GREATEST(:delta, 0) "
            + "WHERE id = :userId AND coins + :delta >= 0 RETURNING coins")
    Mono<Long> adjustCoins(UUID userId, long delta);

    @Query("SELECT lifetime_coins FROM users WHERE id = :userId")
    Mono<Long> lifetimeCoinsOf(UUID userId);
}
