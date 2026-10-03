package app.truearena;

import app.truearena.api.championship.ChampionshipService;
import app.truearena.persistence.ChampionshipMatchRepository;
import app.truearena.persistence.ChampionshipMatchRow;
import app.truearena.persistence.GameSessionRepository;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Full wiring against real Postgres + Redis — same rig as {@link ContextLoadsIT}. This
 * exercises {@code ChampionshipService} through its real public API (not mocks), which is
 * the only way to meaningfully test its SQL: bracket seeding, round advancement under
 * PostgreSQL's own CAS guard, and reconnect-allowance bookkeeping. Game outcomes are
 * injected directly via {@code gameFinished} — this is a tournament-logic test, not a
 * Draughts-rules test (see {@code DraughtsModuleCoverageTest} for that) — but match rooms,
 * sessions, and the Draughts game itself are the real thing {@code startTournamentRoom}
 * creates, so the room/session plumbing this depends on is exercised for real too.
 */
@SpringBootTest
@Tag("integration")
@Testcontainers
class ChampionshipServiceIT {

    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16");

    @Container
    static final GenericContainer<?> REDIS = new GenericContainer<>("redis:7").withExposedPorts(6379);

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.r2dbc.url", () -> "r2dbc:postgresql://" + POSTGRES.getHost() + ":"
                + POSTGRES.getFirstMappedPort() + "/" + POSTGRES.getDatabaseName());
        r.add("spring.r2dbc.username", POSTGRES::getUsername);
        r.add("spring.r2dbc.password", POSTGRES::getPassword);
        r.add("spring.flyway.url", POSTGRES::getJdbcUrl);
        r.add("spring.flyway.user", POSTGRES::getUsername);
        r.add("spring.flyway.password", POSTGRES::getPassword);
        r.add("spring.data.redis.host", REDIS::getHost);
        r.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
    }

    @Autowired ChampionshipService championships;
    @Autowired UserRepository users;
    @Autowired ChampionshipMatchRepository matches;
    @Autowired GameSessionRepository sessions;
    @Autowired DatabaseClient db;

    private UUID user(String tag) {
        String unique = (tag + UUID.randomUUID()).replace("-", "");
        return users.save(UserRow.newUser(null, unique + "@championship.test", "Player " + tag, "cup_" + unique))
                .map(UserRow::id).block();
    }

    /** Injects a server-computed result for a match's current game, as the Draughts
     * adapter does when a real game concludes — see {@code GameOrchestrator.finishGame}. */
    private void resolve(UUID roomId, UUID winner, UUID loser) {
        UUID sessionId = sessions.findFirstByRoomIdOrderByStartedAtDesc(roomId).blockOptional()
                .orElseThrow(() -> new IllegalStateException("no game session for room " + roomId)).id();
        Map<String, String> outcome = winner == null ? Map.of()
                : Map.of(winner.toString(), "won", loser.toString(), "lost");
        championships.gameFinished(roomId, sessionId, outcome).block();
    }

    @Test
    void fourPlayerBracketAdvancesToAChampionAndAwardsABadge() {
        UUID creator = user("a-creator");
        UUID p2 = user("a-p2");
        UUID p3 = user("a-p3");
        UUID p4 = user("a-p4");

        UUID id = championships.create(creator, "IT Cup", 4, "public", Instant.now().plusSeconds(30))
                .block().id();
        championships.join(id, p2).block();
        championships.join(id, p3).block();
        ChampionshipService.View full = championships.join(id, p4).block();
        assertThat(full.joined()).isEqualTo(4);
        assertThat(full.status()).isEqualTo("lobby");

        ChampionshipService.View started = championships.startNow(id, creator).block();
        assertThat(started.status()).isEqualTo("running");
        assertThat(started.currentRound()).isEqualTo(1);

        List<ChampionshipMatchRow> round1 = matches.findByChampionshipIdAndRoundOrderByPositionAsc(id, 1)
                .collectList().block();
        assertThat(round1).hasSize(2);
        assertThat(round1).allSatisfy(m -> {
            assertThat(m.playerA()).isNotNull();
            assertThat(m.playerB()).isNotNull();
            assertThat(m.roomId()).isNotNull();
            assertThat(m.status()).isEqualTo("active");
        });

        // Every entrant appears exactly once across round 1 — the bracket's basic invariant.
        Set<UUID> round1Entrants = round1.stream()
                .flatMap(m -> java.util.stream.Stream.of(m.playerA(), m.playerB()))
                .collect(java.util.stream.Collectors.toSet());
        assertThat(round1Entrants).containsExactlyInAnyOrder(creator, p2, p3, p4);

        // playerA wins each pairing — deterministic regardless of bracket seeding order.
        List<UUID> finalists = round1.stream().map(ChampionshipMatchRow::playerA).toList();
        for (ChampionshipMatchRow m : round1) {
            resolve(m.roomId(), m.playerA(), m.playerB());
        }

        ChampionshipService.View midway = championships.detail(id, creator).block();
        List<ChampionshipService.Match> round2 = midway.matches().stream().filter(m -> m.round() == 2).toList();
        assertThat(round2).hasSize(1);
        ChampionshipService.Match finalMatch = round2.get(0);
        assertThat(Set.of(finalMatch.playerA(), finalMatch.playerB())).isEqualTo(Set.copyOf(finalists));
        assertThat(finalMatch.status()).isEqualTo("active");
        assertThat(finalMatch.roomId()).isNotNull();

        resolve(finalMatch.roomId(), finalMatch.playerA(), finalMatch.playerB());

        ChampionshipService.View done = championships.detail(id, creator).block();
        assertThat(done.status()).isEqualTo("completed");
        assertThat(done.championId()).isEqualTo(finalMatch.playerA());

        List<ChampionshipService.Badge> badges = championships.badges(finalMatch.playerA()).collectList().block();
        assertThat(badges).extracting(ChampionshipService.Badge::championshipId).contains(id);
    }

    @Test
    void joiningAFullChampionshipIsRefused() {
        UUID creator = user("b-creator");
        UUID p2 = user("b-p2");
        UUID p3 = user("b-p3");
        UUID p4 = user("b-p4");
        UUID p5 = user("b-p5");
        UUID id = championships.create(creator, "Full Cup", 4, "public", Instant.now().plusSeconds(30))
                .block().id();
        championships.join(id, p2).block();
        championships.join(id, p3).block();
        championships.join(id, p4).block();

        assertThatConflict(() -> championships.join(id, p5).block());
    }

    @Test
    void onlyTheCreatorCanStartEarly() {
        UUID creator = user("c-creator");
        UUID p2 = user("c-p2");
        UUID p3 = user("c-p3");
        UUID p4 = user("c-p4");
        UUID id = championships.create(creator, "Creator-only Cup", 4, "public", Instant.now().plusSeconds(30))
                .block().id();
        championships.join(id, p2).block();
        championships.join(id, p3).block();
        championships.join(id, p4).block();

        assertThatForbidden(() -> championships.startNow(id, p2).block());
    }

    @Test
    void aDrawReplaysThePairingWithoutResettingTheReconnectAllowance() {
        UUID creator = user("d-creator");
        UUID p2 = user("d-p2");
        UUID p3 = user("d-p3");
        UUID p4 = user("d-p4");
        UUID id = championships.create(creator, "Draw Cup", 4, "public", Instant.now().plusSeconds(30))
                .block().id();
        championships.join(id, p2).block();
        championships.join(id, p3).block();
        championships.join(id, p4).block();
        championships.startNow(id, creator).block();

        ChampionshipMatchRow m = matches.findByChampionshipIdAndRoundOrderByPositionAsc(id, 1)
                .blockFirst();
        UUID roomId = m.roomId();
        assertThat(m.aRemainingMs()).isEqualTo(180_000L);

        // playerA was absent for 130 of their 180 seconds, then reconnected —
        // banking roughly 50 seconds rather than the full allowance.
        db.sql("UPDATE championship_matches SET a_absent_since = :since WHERE id = :id")
                .bind("since", Instant.now().minusSeconds(130)).bind("id", m.id())
                .fetch().rowsUpdated().block();
        championships.connection(roomId, m.playerA(), true).block();

        long banked = matches.findById(m.id()).block().aRemainingMs();
        assertThat(banked).isLessThan(180_000L).isGreaterThan(0L);

        // The game draws — same pairing, a fresh game, but the same running allowance.
        resolve(roomId, null, null);

        ChampionshipMatchRow replay = matches.findById(m.id()).block();
        assertThat(replay.gameNumber()).isEqualTo(2);
        assertThat(replay.status()).isEqualTo("active");
        assertThat(replay.roomId()).isNotEqualTo(roomId);
        assertThat(replay.aRemainingMs())
                .as("a draw must not hand back a fresh 3 minutes — the allowance is scoped to the whole pairing")
                .isEqualTo(banked);
    }

    @Test
    void endingABothAbsentPairingRequiresBothAllowancesToHaveTrulyExpired() {
        UUID creator = user("e-creator");
        UUID p2 = user("e-p2");
        UUID p3 = user("e-p3");
        UUID p4 = user("e-p4");
        UUID id = championships.create(creator, "Stall Cup", 4, "public", Instant.now().plusSeconds(30))
                .block().id();
        championships.join(id, p2).block();
        championships.join(id, p3).block();
        championships.join(id, p4).block();
        championships.startNow(id, creator).block();
        UUID matchId = matches.findByChampionshipIdAndRoundOrderByPositionAsc(id, 1).blockFirst().id();

        // Both allowances are still running — the admin cannot end it yet.
        assertThatConflict(() -> championships.endBothAbsent(matchId, creator).block());

        db.sql("UPDATE championship_matches SET a_absent_since = :t, b_absent_since = :t WHERE id = :id")
                .bind("t", Instant.now().minusSeconds(200)).bind("id", matchId)
                .fetch().rowsUpdated().block();

        // Only the championship's creator is the tournament admin (see the spec's
        // "Implemented decisions") — anyone else is refused even once both expired.
        assertThatForbidden(() -> championships.endBothAbsent(matchId, p2).block());

        championships.endBothAbsent(matchId, creator).block();
        ChampionshipMatchRow ended = matches.findById(matchId).block();
        assertThat(ended.status()).isEqualTo("no_winner");
        assertThat(ended.winnerId()).isNull();
    }

    private static void assertThatConflict(Runnable action) {
        assertThat(org.junit.jupiter.api.Assertions.assertThrows(
                org.springframework.web.server.ResponseStatusException.class, action::run).getStatusCode().value())
                .isEqualTo(409);
    }

    private static void assertThatForbidden(Runnable action) {
        assertThat(org.junit.jupiter.api.Assertions.assertThrows(
                org.springframework.web.server.ResponseStatusException.class, action::run).getStatusCode().value())
                .isEqualTo(403);
    }
}
