package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * One friend pair — table predates this feature's UI (Phase 1, V1__core.sql)
 * but was never built on until now. Stored with an ordered pair
 * ({@code lowUserId < highUserId}) so (a,b) and (b,a) can never both exist —
 * enforced by a DB CHECK, not just application logic.
 *
 * <p>{@code status} is {@code "pending"} or {@code "accepted"} — there's no
 * {@code "declined"} state: declining (or unfriending) just deletes the row,
 * so a fresh request can always be sent again later without a stale record
 * in the way.
 */
@Table("friends")
public record FriendRow(
        @Id UUID id,
        @Column("low_user_id") UUID lowUserId,
        @Column("high_user_id") UUID highUserId,
        String status,
        @Column("requested_by") UUID requestedBy,
        @Column("created_at") Instant createdAt
) {
    public static final String PENDING = "pending";
    public static final String ACCEPTED = "accepted";

    /**
     * Builds the row with the pair correctly ordered regardless of who's "a"
     * and who's "b" — ordered by string form, not {@link UUID#compareTo},
     * which compares {@code mostSigBits}/{@code leastSigBits} as *signed*
     * longs and so disagrees with Postgres's byte-wise {@code uuid}
     * ordering roughly half the time (whenever the high bit of either half
     * differs) — that mismatch is exactly what was tripping the DB's
     * {@code low_user_id < high_user_id} CHECK. String comparison of the
     * canonical hex form has no sign bit to disagree about, so it always
     * agrees with Postgres.
     */
    public static FriendRow requested(UUID requesterId, UUID otherId) {
        UUID low = lowerOf(requesterId, otherId);
        UUID high = low.equals(requesterId) ? otherId : requesterId;
        return new FriendRow(null, low, high, PENDING, requesterId, null);
    }

    /**
     * The Postgres-agreeing "lower" of two ids — string comparison, not
     * {@link UUID#compareTo}. Exposed so every caller ordering a pair (row
     * construction, row lookup) uses the exact same rule; see the field doc
     * above for why {@code UUID#compareTo} disagrees with Postgres here.
     */
    public static UUID lowerOf(UUID a, UUID b) {
        return a.toString().compareTo(b.toString()) < 0 ? a : b;
    }

    public FriendRow accepted() {
        return new FriendRow(id, lowUserId, highUserId, ACCEPTED, requestedBy, createdAt);
    }

    /** The id of the other user in this pair, given one side of it. */
    public UUID otherUser(UUID selfId) {
        return lowUserId.equals(selfId) ? highUserId : lowUserId;
    }
}
