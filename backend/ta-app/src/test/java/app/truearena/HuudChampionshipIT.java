package app.truearena;

import app.truearena.api.championship.ChampionshipService;
import app.truearena.api.huudspace.HuudChampionshipService;
import app.truearena.api.huudspace.HuudSpaceAccess;
import app.truearena.api.huudspace.HuudSpaceDtos.ChampionshipMatch;
import app.truearena.api.huudspace.HuudSpaceDtos.ChampionshipRequest;
import app.truearena.api.huudspace.HuudSpaceDtos.HuudChampionship;
import app.truearena.api.huudspace.HuudSpaceRequestService;
import app.truearena.api.huudspace.HuudSpaceService;
import app.truearena.persistence.GameSessionRepository;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.voice.LiveKitRoomAdmin;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.web.server.ResponseStatusException;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import reactor.core.publisher.Mono;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

/**
 * A Chess or Draughts championship inside a Huud, end to end on the real
 * bracket: registration, the system draw, simultaneous and sequential rounds,
 * the one-activity rule, match voice, and the Huud going back to hanging out.
 * Game results are injected the way {@code GameOrchestrator.finishGame} does.
 * Runs against {@code -Dit.r2dbc.url=…} like {@link HuudSpaceIT}, or Testcontainers.
 */
@SpringBootTest
@Tag("integration")
class HuudChampionshipIT {
    private static final boolean EXTERNAL = System.getProperty("it.r2dbc.url") != null;
    private static final PostgreSQLContainer<?> POSTGRES = EXTERNAL ? null : new PostgreSQLContainer<>("postgres:16");
    private static final GenericContainer<?> REDIS = EXTERNAL ? null
            : new GenericContainer<>("redis:7").withExposedPorts(6379);

    static {
        if (!EXTERNAL) {
            POSTGRES.start();
            REDIS.start();
        }
    }

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        if (EXTERNAL) {
            r.add("spring.r2dbc.url", () -> System.getProperty("it.r2dbc.url"));
            r.add("spring.r2dbc.username", () -> System.getProperty("it.db.user"));
            r.add("spring.r2dbc.password", () -> System.getProperty("it.db.password"));
            r.add("spring.flyway.url", () -> System.getProperty("it.jdbc.url"));
            r.add("spring.flyway.user", () -> System.getProperty("it.db.user"));
            r.add("spring.flyway.password", () -> System.getProperty("it.db.password"));
            r.add("spring.data.redis.host", () -> System.getProperty("it.redis.host", "localhost"));
            r.add("spring.data.redis.port", () -> System.getProperty("it.redis.port", "6379"));
            r.add("spring.data.redis.database", () -> System.getProperty("it.redis.database", "0"));
            return;
        }
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

    @Autowired HuudSpaceService huuds;
    @Autowired HuudSpaceRequestService requests;
    @Autowired HuudChampionshipService cups;
    @Autowired ChampionshipService championships;
    @Autowired HuudSpaceAccess access;
    @Autowired GameSessionRepository sessions;
    @Autowired UserRepository users;
    @Autowired DatabaseClient db;
    @MockBean LiveKitRoomAdmin livekit;

    @BeforeEach void media() {
        when(livekit.remove(anyString(), anyString())).thenReturn(Mono.empty());
        when(livekit.setCanPublish(anyString(), anyString(), anyBoolean())).thenReturn(Mono.empty());
    }

    UUID person(String name) {
        String tag = UUID.randomUUID().toString().replace("-", "").substring(0, 15);
        return users.save(UserRow.newUser(null, tag + "@cup.test", name, "c_" + tag)).block().id();
    }

    /** A public Live Huud with its owner and {@code others} members in the hangout. */
    record Room(UUID id, UUID host, List<UUID> members) {}

    Room huudWith(int others) {
        UUID host = person("Host");
        var huud = huuds.create(host, null, "public").block();
        List<UUID> people = new ArrayList<>();
        for (int i = 0; i < others; i++) {
            UUID p = person("Player " + i);
            huuds.joinByCode(p, huud.code()).block();
            people.add(p);
        }
        return new Room(huud.id(), host, people);
    }

    ChampionshipRequest chess(int size, String timing) {
        return new ChampionshipRequest("chess", size, timing, true, 3, null);
    }

    /** What {@code GameOrchestrator.finishGame} hands the bracket when a board ends. */
    void win(ChampionshipMatch m, UUID winner) {
        UUID loser = winner.equals(m.playerA()) ? m.playerB() : m.playerA();
        UUID session = sessions.findFirstByRoomIdOrderByStartedAtDesc(m.roomId()).block().id();
        championships.gameFinished(m.roomId(), session, Map.of(winner.toString(), "won", loser.toString(), "lost")).block();
    }

    List<ChampionshipMatch> live(HuudChampionship c) {
        return c.matches().stream().filter(m -> "active".equals(m.status())).toList();
    }

    @Test void eightPlayersPlayQuarterFinalsTogetherThenSemisThenAStandaloneFinal() {
        Room r = huudWith(8);
        HuudChampionship cup = cups.create(r.host(), r.id(), chess(8, "simultaneous")).block();
        assertThat(cup.status()).isEqualTo("registering");
        assertThat(huuds.mine(r.host()).filter(h -> h.id().equals(r.id())).blockFirst().championship().status())
                .isEqualTo("registering");
        assertThat(cup.name()).isEqualTo("Chess Championship");
        assertThat(huuds.view(r.id(), r.host()).block().championshipId()).isEqualTo(cup.id());

        // The championship is the Huud's activity: no ordinary game alongside it.
        assertThatThrownBy(() -> huuds.addGame(r.host(), r.id(), "whot").block())
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("championship");

        for (int i = 0; i < 7; i++) cups.register(r.members().get(i), r.id()).block();
        assertThat(cups.view(r.id(), r.host()).block().status()).isEqualTo("registering");
        // The last place locks registration and the system draws the bracket.
        HuudChampionship drawn = cups.register(r.members().get(7), r.id()).block();
        assertThat(drawn.status()).isEqualTo("playing");
        assertThat(drawn.roundName()).isEqualTo("Quarter Finals");
        // The Huud's cards on the Live and Huud tabs say so.
        var line = new app.truearena.api.huudspace.HuudSpaceDtos.ChampionshipLine(
                "Chess Championship", "chess", "playing", "Quarter Finals");
        assertThat(huuds.live(r.members().get(0)).filter(h -> h.id().equals(r.id())).blockFirst().championship())
                .isEqualTo(line);
        assertThat(huuds.mine(r.host()).filter(h -> h.id().equals(r.id())).blockFirst().championship())
                .isEqualTo(line);
        assertThat(drawn.rounds()).isEqualTo(3);
        assertThatThrownBy(() -> cups.register(r.host(), r.id()).block()).isInstanceOf(ResponseStatusException.class);

        List<ChampionshipMatch> quarters = live(drawn);
        assertThat(quarters).hasSize(4).allSatisfy(m -> {
            assertThat(m.roundName()).isEqualTo("Quarter Finals");
            assertThat(m.voiceRoom()).isEqualTo(HuudSpaceAccess.matchVoiceRoom(r.id(), m.id()));
        });
        Set<UUID> seated = new HashSet<>();
        quarters.forEach(m -> { seated.add(m.playerA()); seated.add(m.playerB()); });
        assertThat(seated).containsExactlyInAnyOrderElementsOf(r.members());
        // Real chess boards, belonging to the Huud.
        for (ChampionshipMatch m : quarters) {
            Map<String, Object> room = db.sql("SELECT game_type, huud_space_id FROM rooms WHERE id=:id")
                    .bind("id", m.roomId()).fetch().one().block();
            assertThat(room).containsEntry("game_type", "chess").containsEntry("huud_space_id", r.id());
        }
        ChampionshipMatch first = quarters.get(0);
        assertThat(cups.view(r.id(), first.playerA()).block().yourMatchId()).isEqualTo(first.id());

        // Match voice: anyone in the Huud may listen; speaking still needs the host's mic.
        UUID player = first.playerA();
        assertThat(access.canTalk(player, first.voiceRoom()).block()).isTrue();
        assertThat(access.canTalk(quarters.get(1).playerA(), first.voiceRoom()).block()).isTrue();
        assertThat(access.canSpeak(player, first.voiceRoom()).block()).isFalse();
        assertThat(access.canSpeak(r.host(), first.voiceRoom()).block()).isTrue();
        requests.setMic(r.host(), r.id(), player, true).block();
        assertThat(access.canSpeak(player, first.voiceRoom()).block()).isTrue();
        assertThat(access.canSpeak(player, "huud-" + r.id()).block()).isTrue();
        UUID outsider = person("Outsider");
        assertThat(access.canTalk(outsider, first.voiceRoom()).block()).isFalse();

        // Quarter Finals: first board done — its voice room closes, the others play on.
        win(first, first.playerA());
        assertThat(access.canTalk(player, first.voiceRoom()).block()).isFalse();
        HuudChampionship waiting = cups.view(r.id(), r.host()).block();
        assertThat(live(waiting)).hasSize(3);
        assertThat(waiting.players().stream().filter(p -> p.out()).map(p -> p.userId())).containsExactly(first.playerB());
        for (ChampionshipMatch m : quarters.subList(1, 4)) win(m, m.playerA());

        HuudChampionship semis = cups.view(r.id(), r.host()).block();
        assertThat(semis.roundName()).isEqualTo("Semi Finals");
        List<ChampionshipMatch> semiBoards = live(semis);
        assertThat(semiBoards).hasSize(2).allSatisfy(m -> assertThat(m.roundName()).isEqualTo("Semi Finals"));
        // Winners progress: Match 1's winner meets Match 2's.
        assertThat(Set.of(semiBoards.get(0).playerA(), semiBoards.get(0).playerB()))
                .containsExactlyInAnyOrder(quarters.get(0).playerA(), quarters.get(1).playerA());
        for (ChampionshipMatch m : semiBoards) win(m, m.playerB());

        HuudChampionship fin = cups.view(r.id(), r.host()).block();
        assertThat(fin.roundName()).isEqualTo("Final");
        assertThat(live(fin)).hasSize(1);
        ChampionshipMatch theFinal = live(fin).get(0);
        win(theFinal, theFinal.playerB());

        HuudChampionship done = cups.view(r.id(), r.host()).block();
        assertThat(done.status()).isEqualTo("finished");
        assertThat(done.championId()).isEqualTo(theFinal.playerB());
        assertThat(done.runnerUpId()).isEqualTo(theFinal.playerA());
        assertThat(live(done)).isEmpty();

        // Hang Out: the Huud carries on as it was, and a normal game can be played again.
        assertThat(huuds.mine(r.host()).filter(h -> h.id().equals(r.id())).blockFirst().championship().status())
                .isEqualTo("finished");
        var back = cups.close(r.host(), r.id()).block();
        assertThat(back.championshipId()).isNull();
        assertThat(huuds.mine(r.host()).filter(h -> h.id().equals(r.id())).blockFirst().championship()).isNull();
        assertThat(back.members()).hasSize(9);
        assertThat(huuds.addGame(r.host(), r.id(), "draughts").block().gameType()).isEqualTo("draughts");
    }

    @Test void sequentialRoundsPlayOneBoardAtATime() {
        Room r = huudWith(4);
        cups.create(r.host(), r.id(), new ChampionshipRequest("draughts", 4, "sequential", false, 1, "Saturday Cup")).block();
        r.members().forEach(p -> cups.register(p, r.id()).block());

        HuudChampionship cup = cups.view(r.id(), r.host()).block();
        assertThat(cup.name()).isEqualTo("Saturday Cup");
        assertThat(cup.graceSeconds()).isEqualTo(60);
        assertThat(live(cup)).hasSize(1);
        ChampionshipMatch one = live(cup).get(0);
        assertThat(one.position()).isEqualTo(1);
        assertThat(one.aReconnectMs()).isLessThanOrEqualTo(60_000L);
        win(one, one.playerA());

        cup = cups.view(r.id(), r.host()).block();
        assertThat(live(cup)).hasSize(1);
        ChampionshipMatch two = live(cup).get(0);
        assertThat(two.position()).isEqualTo(2);
        assertThat(two.roundName()).isEqualTo("Semi Finals");
        win(two, two.playerA());

        cup = cups.view(r.id(), r.host()).block();
        assertThat(live(cup)).hasSize(1).first().satisfies(m -> assertThat(m.roundName()).isEqualTo("Final"));
    }

    @Test void registrationIsForMembersAndCanBeUndoneOrCalledOff() {
        Room r = huudWith(3);
        assertThatThrownBy(() -> cups.create(r.members().get(0), r.id(), chess(4, null)).block())
                .isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> cups.create(r.host(), r.id(), new ChampionshipRequest("whot", 4, null, true, 3, null)).block())
                .isInstanceOf(ResponseStatusException.class);
        HuudChampionship cup = cups.create(r.host(), r.id(), chess(4, null)).block();
        assertThatThrownBy(() -> cups.create(r.host(), r.id(), chess(8, null)).block())
                .isInstanceOf(ResponseStatusException.class);

        // Outsiders and the old invitation path can't take a place.
        assertThatThrownBy(() -> cups.register(person("Stranger"), r.id()).block()).isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> championships.join(cup.id(), r.members().get(0)).block())
                .isInstanceOf(ResponseStatusException.class);

        cups.register(r.host(), r.id()).block();
        cups.register(r.members().get(0), r.id()).block();
        cups.register(r.members().get(1), r.id()).block();
        assertThat(cups.withdraw(r.members().get(0), r.id()).block().players()).hasSize(2);
        assertThat(cups.removePlayer(r.host(), r.id(), r.members().get(1)).block().youAreRegistered()).isTrue();
        // Places freed up are places again.
        cups.register(r.members().get(0), r.id()).block();
        cups.register(r.members().get(1), r.id()).block();
        assertThat(cups.view(r.id(), r.host()).block().players()).hasSize(3);

        // Calling it off: back to hanging out; the registration is history.
        assertThat(cups.close(r.host(), r.id()).block().championshipId()).isNull();
        String status = db.sql("SELECT status FROM championships WHERE id=:id").bind("id", cup.id())
                .map((row, m) -> row.get("status", String.class)).one().block();
        assertThat(status).isEqualTo("cancelled");
    }

    @Test void aChampionshipBeingPlayedCantBePutAwayButEndingLiveCallsOffRegistration() {
        Room r = huudWith(4);
        cups.create(r.host(), r.id(), chess(4, null)).block();
        r.members().forEach(p -> cups.register(p, r.id()).block());
        assertThatThrownBy(() -> cups.close(r.host(), r.id()).block())
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("still being played");

        Room other = huudWith(1);
        HuudChampionship open = cups.create(other.host(), other.id(), chess(4, null)).block();
        huuds.endLive(other.host(), other.id()).block();
        assertThat(huuds.view(other.id(), other.host()).block().championshipId()).isNull();
        String status = db.sql("SELECT status FROM championships WHERE id=:id").bind("id", open.id())
                .map((row, m) -> row.get("status", String.class)).one().block();
        assertThat(status).isEqualTo("cancelled");
    }

    @Test void aGameBeingPlayedHasToFinishBeforeAChampionshipButAWaitingOneIsPutAway() {
        Room r = huudWith(1);
        huuds.addGame(r.host(), r.id(), "whot").block();
        HuudChampionship cup = cups.create(r.host(), r.id(), chess(4, null)).block();
        assertThat(cup.status()).isEqualTo("registering");
        assertThat(huuds.view(r.id(), r.host()).block().currentGame()).isNull();
    }
}
