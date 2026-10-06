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

    @Query("SELECT EXISTS (SELECT 1 FROM users WHERE lower(username) = lower(:username))")
    Mono<Boolean> existsByUsernameIgnoreCase(String username);

    @Query("SELECT EXISTS (SELECT 1 FROM users WHERE lower(username) = lower(:username) AND id <> :userId)")
    Mono<Boolean> existsByUsernameIgnoreCaseForOtherUser(String username, UUID userId);

    /** Legacy saved-agent lookup retained for rolling-client compatibility. */
    @Query("SELECT * FROM users WHERE is_bot AND owner_user_id = :ownerId AND bot_game_type = :gameType "
            + "ORDER BY created_at")
    Flux<UserRow> findAgentsOf(UUID ownerId, String gameType);

    /** Legacy saved-agent lookup retained while pre-pool rows exist. */
    @Query("SELECT * FROM users WHERE is_bot AND owner_user_id = :ownerId ORDER BY created_at")
    Flux<UserRow> findAgentsOf(UUID ownerId);

    /**
     * Picks a reusable system identity that is not already seated in this
     * room. The same identity may be used in other rooms at the same time;
     * room-scoped name, difficulty and runtime state keep those games isolated.
     */
    @Query("SELECT u.* FROM users u WHERE u.is_bot AND u.owner_user_id IS NULL "
            + "AND u.bot_game_type = 'system_pool' "
            + "AND NOT EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = :roomId AND m.user_id = u.id) "
            + "ORDER BY u.username LIMIT 1")
    Mono<UserRow> findSystemAgentForRoom(UUID roomId);

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

    /**
     * Permanent PlayHuud number. Deliberately not a {@link UserRow} field, for
     * the same reason {@code coins} isn't: the database assigns it (a BEFORE
     * INSERT trigger) and freezes it (a BEFORE UPDATE trigger), so an entity
     * copy would be stale straight after {@code save()}. Empty for bots.
     */
    @Query("SELECT playhuud_number FROM users WHERE id = :userId AND playhuud_number IS NOT NULL")
    Mono<Long> playhuudNumberOf(UUID userId);

    /**
     * Friend search-as-you-type — matches either handle, real humans only
     * (no bots), never the searcher themself. Exact and prefix username
     * matches rank first, then a prefix match on the real name, so typing
     * a few characters of either surfaces the right person before anyone
     * who merely contains the substring elsewhere in their name.
     */
    @Query("SELECT * FROM users WHERE NOT is_bot AND id <> :selfId "
            + "AND (username ILIKE '%' || :q || '%' OR display_name ILIKE '%' || :q || '%') "
            + "ORDER BY (lower(username) = lower(:q)) DESC, "
            + "(username ILIKE :q || '%') DESC, "
            + "(display_name ILIKE :q || '%') DESC, "
            + "username "
            + "LIMIT 10")
    Flux<UserRow> searchByUsernameOrDisplayName(String q, UUID selfId);
}
