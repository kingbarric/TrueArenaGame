package app.truearena.api.championship;

import app.truearena.api.ws.GameOrchestrator;
import app.truearena.persistence.ChampionshipMatchRepository;
import app.truearena.persistence.ChampionshipMatchRow;
import app.truearena.persistence.ChampionshipRepository;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.UserRepository;
import app.truearena.room.RoomRuntimeRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.r2dbc.core.DatabaseClient;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * {@link ChampionshipService#forfeitAllowed} decides whether a disconnected
 * player's opponent should win by forfeit — the one-sided-absence case from
 * docs/DRAUGHTS_CHAMPIONSHIPS.md. The both-absent case (an admin decision,
 * not automatic) is the negative space this test spends most of its cases on.
 * Pure logic over a hand-built row, no database needed.
 */
@SuppressWarnings("unchecked")
class ChampionshipServiceForfeitTest {
    private final ChampionshipMatchRepository matches = mock(ChampionshipMatchRepository.class);
    private final ChampionshipService service = new ChampionshipService(
            mock(ChampionshipRepository.class), matches, mock(UserRepository.class),
            mock(RoomRepository.class), mock(RoomMemberRepository.class),
            mock(RoomRuntimeRegistry.class), mock(DatabaseClient.class),
            mock(ObjectProvider.class));

    private static final UUID ROOM = UUID.randomUUID();
    private static final UUID PLAYER_A = UUID.randomUUID();
    private static final UUID PLAYER_B = UUID.randomUUID();

    private ChampionshipMatchRow activeMatch(Instant aAbsentSince, Instant bAbsentSince) {
        return new ChampionshipMatchRow(UUID.randomUUID(), UUID.randomUUID(), 1, 1, PLAYER_A, PLAYER_B,
                null, "active", ROOM, 1, 180_000, 180_000, aAbsentSince, bAbsentSince, Instant.now(), null);
    }

    private void stub(ChampionshipMatchRow row) {
        when(matches.findByRoomId(ROOM)).thenReturn(Mono.just(row));
    }

    @Test
    void loserForfeitsWhenOnlyTheyHaveExpired() {
        // playerA has been absent 4 minutes (past the 3-minute allowance); playerB never left.
        stub(activeMatch(Instant.now().minus(4, ChronoUnit.MINUTES), null));
        StepVerifier.create(service.forfeitAllowed(ROOM, PLAYER_A)).expectNext(true).verifyComplete();
    }

    @Test
    void opponentDoesNotForfeitWhileStillWithinAllowance() {
        // playerA absent only 30 seconds — well inside the 3-minute grace.
        stub(activeMatch(Instant.now().minus(30, ChronoUnit.SECONDS), null));
        StepVerifier.create(service.forfeitAllowed(ROOM, PLAYER_A)).expectNext(false).verifyComplete();
    }

    @Test
    void neitherPlayerAbsentNeverForfeits() {
        stub(activeMatch(null, null));
        StepVerifier.create(service.forfeitAllowed(ROOM, PLAYER_A)).expectNext(false).verifyComplete();
        StepVerifier.create(service.forfeitAllowed(ROOM, PLAYER_B)).expectNext(false).verifyComplete();
    }

    @Test
    void bothExpiredIsAnAdminDecisionNotAnAutomaticForfeit() {
        // The spec is explicit: once *both* allowances expire, only an authorized
        // admin can end the pairing — the server must never pick a winner itself.
        Instant longAgo = Instant.now().minus(10, ChronoUnit.MINUTES);
        stub(activeMatch(longAgo, longAgo));
        StepVerifier.create(service.forfeitAllowed(ROOM, PLAYER_A)).expectNext(false).verifyComplete();
        StepVerifier.create(service.forfeitAllowed(ROOM, PLAYER_B)).expectNext(false).verifyComplete();
    }

    @Test
    void checksTheRequestedLoserNotJustAnyAbsentPlayer() {
        // Only playerA is absent (and expired) — asking about playerB (who is
        // present) must not say "forfeit", even though *someone* has expired.
        stub(activeMatch(Instant.now().minus(4, ChronoUnit.MINUTES), null));
        StepVerifier.create(service.forfeitAllowed(ROOM, PLAYER_B)).expectNext(false).verifyComplete();
    }

    @Test
    void noForfeitOnceTheMatchHasAlreadyMovedOn() {
        ChampionshipMatchRow completed = new ChampionshipMatchRow(UUID.randomUUID(), UUID.randomUUID(), 1, 1,
                PLAYER_A, PLAYER_B, PLAYER_B, "completed", ROOM, 1, 180_000, 180_000,
                Instant.now().minus(4, ChronoUnit.MINUTES), null, Instant.now(), Instant.now());
        stub(completed);
        StepVerifier.create(service.forfeitAllowed(ROOM, PLAYER_A)).expectNext(false).verifyComplete();
    }

    @Test
    void unknownRoomNeverForfeits() {
        when(matches.findByRoomId(any())).thenReturn(Mono.empty());
        StepVerifier.create(service.forfeitAllowed(ROOM, PLAYER_A)).expectNext(false).verifyComplete();
    }
}
