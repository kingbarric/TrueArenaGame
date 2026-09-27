package app.truearena.persistence;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Regression coverage for a real bug: {@link UUID#compareTo} orders by
 * {@code mostSigBits}/{@code leastSigBits} as <em>signed</em> longs, which
 * disagrees with Postgres's byte-wise {@code uuid} ordering whenever the
 * high bit of either half differs between the two ids — roughly half of all
 * random UUID pairs. That mismatch made {@code POST /friends/requests}
 * intermittently 500 in production-shaped testing (a live E2E run against
 * real Postgres, not the unit-test mocks) by building a row that failed the
 * {@code low_user_id < high_user_id} CHECK. {@link FriendRow#lowerOf} fixes
 * it with string comparison instead — this test pins down the exact pair
 * that proved it, so the fix can't silently regress back to
 * {@code UUID#compareTo}.
 */
class FriendRowTest {

    @Test
    void lowerOfDisagreesWithUuidCompareToOnAKnownAdversarialPair() {
        // Chosen so the two orderings actually disagree — the whole point of
        // this test. mostSigBits differ only in the sign bit: one starts with
        // hex digit 7 (positive as a signed long), the other with 8 (negative).
        UUID a = UUID.fromString("70000000-0000-0000-0000-000000000000");
        UUID b = UUID.fromString("80000000-0000-0000-0000-000000000000");

        // Signed-long compareTo says a > b (a's high bit is 0/positive, b's is
        // 1/negative) — the opposite of string/byte-wise order.
        assertThat(a.compareTo(b)).isGreaterThan(0);
        // String (and Postgres byte-wise) order says a < b, correctly.
        assertThat(a.toString().compareTo(b.toString())).isLessThan(0);

        assertThat(FriendRow.lowerOf(a, b)).isEqualTo(a);
        assertThat(FriendRow.lowerOf(b, a)).isEqualTo(a); // order of arguments doesn't matter
    }

    @ParameterizedTest
    @CsvSource({
            "70000000-0000-0000-0000-000000000000, 80000000-0000-0000-0000-000000000000",
            "00000000-0000-0000-0000-000000000001, ffffffff-0000-0000-0000-000000000000",
            "11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222",
    })
    void requestedAlwaysOrdersLowBeforeHighRegardlessOfWhoRequests(UUID x, UUID y) {
        // Whichever of the two calls first, the stored pair must come out
        // identically ordered — that's what lets the other side's lookup find
        // the same row.
        FriendRow fromX = FriendRow.requested(x, y);
        FriendRow fromY = FriendRow.requested(y, x);

        assertThat(fromX.lowUserId()).isEqualTo(fromY.lowUserId());
        assertThat(fromX.highUserId()).isEqualTo(fromY.highUserId());
        assertThat(fromX.lowUserId().toString()).isLessThan(fromX.highUserId().toString());
    }

    @Test
    void requestedKeepsTrackOfWhoActuallyAsked() {
        UUID x = UUID.randomUUID();
        UUID y = UUID.randomUUID();
        FriendRow row = FriendRow.requested(x, y);
        assertThat(row.requestedBy()).isEqualTo(x);
        assertThat(row.status()).isEqualTo(FriendRow.PENDING);
    }

    @Test
    void otherUserReturnsWhicheverSideIsntSelf() {
        UUID x = UUID.randomUUID();
        UUID y = UUID.randomUUID();
        FriendRow row = FriendRow.requested(x, y);
        assertThat(row.otherUser(x)).isEqualTo(y);
        assertThat(row.otherUser(y)).isEqualTo(x);
    }
}
