package app.truearena;

import static org.assertj.core.api.Assertions.*;

import app.truearena.api.slay.*;
import app.truearena.engine.slay.SlayRules.*;
import app.truearena.persistence.*;

import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.*;

import java.time.*;
import java.util.*;

@SpringBootTest
@Tag("integration")
class SlayHuudIT {
    private static final boolean EXTERNAL = System.getProperty("it.r2dbc.url") != null;
    private static final PostgreSQLContainer<?> POSTGRES =
            EXTERNAL ? null : new PostgreSQLContainer<>("postgres:16");
    private static final GenericContainer<?> REDIS =
            EXTERNAL ? null : new GenericContainer<>("redis:7").withExposedPorts(6379);

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
        r.add(
                "spring.r2dbc.url",
                () ->
                        "r2dbc:postgresql://"
                                + POSTGRES.getHost()
                                + ":"
                                + POSTGRES.getFirstMappedPort()
                                + "/"
                                + POSTGRES.getDatabaseName());
        r.add("spring.r2dbc.username", POSTGRES::getUsername);
        r.add("spring.r2dbc.password", POSTGRES::getPassword);
        r.add("spring.flyway.url", POSTGRES::getJdbcUrl);
        r.add("spring.flyway.user", POSTGRES::getUsername);
        r.add("spring.flyway.password", POSTGRES::getPassword);
        r.add("spring.data.redis.host", REDIS::getHost);
        r.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
    }

    @Autowired app.truearena.api.championship.ChampionshipService cups;
    @Autowired com.fasterxml.jackson.databind.ObjectMapper json;
    @Autowired SlayService slay;
    @Autowired app.truearena.api.huud.HuudService huud;
    @Autowired UserRepository users;
    @Autowired DatabaseClient db;

    UUID human() {
        String name = "slay_" + UUID.randomUUID().toString().substring(0, 8);
        UUID id = users.save(UserRow.newUser(null, name + "@test.local", name, name)).block().id();
        db.sql("UPDATE users SET created_at=now()-interval '2 days',coins=200 WHERE id=:u")
                .bind("u", id)
                .fetch()
                .rowsUpdated()
                .block();
        return id;
    }

    Look outfit(String body) {
        return new Look(
                body,
                "#623a27",
                "classic",
                Map.of(
                        "outfit",
                        body + "-owambe",
                        "hair",
                        body + "-hair-0",
                        "shoes",
                        "shoe-3",
                        "jewellery",
                        "accessory-0"),
                "signature",
                "studio");
    }

    UUID saved(UUID user, String body) {
        var l = slay.saveLook(user, outfit(body)).block();
        try {
            var buffer = new java.io.ByteArrayOutputStream();
            javax.imageio.ImageIO.write(
                    new java.awt.image.BufferedImage(
                            60, 90, java.awt.image.BufferedImage.TYPE_INT_RGB),
                    "png",
                    buffer);
            slay.snapshot(user, l.id(), Base64.getEncoder().encodeToString(buffer.toByteArray()))
                    .block();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
        return l.id();
    }

    void due(UUID id) {
        db.sql(
                        "UPDATE slay_competitions SET"
                                + " state=jsonb_set(state,'{deadline}',to_jsonb(CAST(:stamp AS"
                                + " text))),deadline=:deadline WHERE id=:id")
                .bind("stamp", Instant.now().minusSeconds(2).toString())
                .bind("deadline", Instant.now().minusSeconds(2))
                .bind("id", id)
                .fetch()
                .rowsUpdated()
                .block();
    }

    @Test
    void battleKeepsLooksPrivateRejectsSelfAndDoubleVotesAndSettlesOnlyOnce() {
        UUID a = human(), b = human(), voter = human();
        UUID id =
                UUID.fromString(
                        (String)
                                slay.create(
                                                a,
                                                new SlayService.Create(
                                                        "battle", "lagos-owambe", 2, "male", true))
                                        .block()
                                        .get("id"));
        slay.join(a, id, new SlayService.Join("contestant", "female")).block();
        slay.join(b, id, new SlayService.Join("contestant", "male")).block();
        slay.start(a, id).block();
        UUID first = saved(a, "female"), second = saved(b, "male");
        assertThatThrownBy(() -> slay.image(b, first).block()).hasMessageContaining("unavailable");
        assertThat(slay.runwayLook(a, first).block().look()).isEqualTo(outfit("female"));
        assertThatThrownBy(() -> slay.runwayLook(voter, first).block())
                .hasMessageContaining("unavailable");
        slay.submit(a, id, first).block();
        assertThat((List<?>) slay.get(b, id).block().get("entries")).isEmpty();
        assertThatThrownBy(() -> slay.submit(a, id, first).block())
                .hasMessageContaining("already submitted");
        slay.submit(b, id, second).block();
        assertThat(slay.image(voter, first).block()).isNotEmpty();
        var runway = slay.runwayLook(voter, first).block();
        assertThat(runway.look()).isEqualTo(outfit("female"));
        assertThat(runway.catalogVersion()).isPositive();
        assertThat(json.valueToTree(runway).fieldNames())
                .toIterable()
                .containsExactlyInAnyOrder("look", "catalogVersion");
        assertThatThrownBy(() -> slay.ballot(a, id).block()).hasMessageContaining("cannot vote");
        var ballot = slay.ballot(voter, id).block();
        assertThat(ballot).isNotNull();
        db.sql("UPDATE slay_ballots SET served_at=now()-interval '2 seconds' WHERE id=:id")
                .bind("id", ballot.id())
                .fetch()
                .rowsUpdated()
                .block();
        slay.vote(voter, ballot.id(), ballot.entryA()).block();
        assertThatThrownBy(() -> slay.vote(voter, ballot.id(), ballot.entryA()).block())
                .hasMessageContaining("already recorded");
        due(id);
        slay.get(a, id).block();
        assertThat(slay.get(a, id).block().get("status")).isEqualTo("results");
        Long coins = users.coinsOf(a).block();
        slay.get(a, id).block();
        assertThat(users.coinsOf(a).block()).isEqualTo(coins);
        assertThat(
                        db.sql("SELECT count(*) AS n FROM match_records WHERE game_session_id=:id")
                                .bind("id", id)
                                .map(r -> r.get("n", Long.class))
                                .one()
                                .block())
                .isEqualTo(1L);
        assertThatThrownBy(() -> slay.ballot(voter, id).block()).hasMessageContaining("closed");
    }

    @Test
    void soloRewardAndWardrobePurchaseAreIdempotent() {
        UUID user = human(), look = saved(user, "female");
        var first = slay.solo(user, "lagos-owambe", look).block();
        Long coins = users.coinsOf(user).block();
        slay.solo(user, "lagos-owambe", look).block();
        assertThat(users.coinsOf(user).block()).isEqualTo(coins);
        assertThat(first.stars()).isEqualTo(3);
        slay.buy(user, "female-royal").block();
        assertThat(slay.wardrobe(user).block()).contains("female-royal");
        assertThatThrownBy(() -> slay.buy(user, "female-royal").block())
                .hasMessageContaining("already own");
    }

    @Test
    void cannotEquipUnownedOrOtherBodyClothing() {
        UUID user = human();
        Look locked =
                new Look(
                        "female",
                        "#623a27",
                        "classic",
                        Map.of("outfit", "female-royal"),
                        "signature",
                        "studio");
        assertThatThrownBy(() -> slay.saveLook(user, locked).block())
                .hasMessageContaining("Unlock");
        Look wrong =
                new Look(
                        "male",
                        "#623a27",
                        "classic",
                        Map.of("outfit", "female-owambe"),
                        "signature",
                        "studio");
        assertThatThrownBy(() -> slay.saveLook(user, wrong).block())
                .hasMessageContaining("does not fit");
    }

    app.truearena.engine.slay.SlayCompetition state(UUID id) {
        return db.sql("SELECT state::text AS state FROM slay_competitions WHERE id=:id")
                .bind("id", id)
                .map(
                        r -> {
                            try {
                                return json.readValue(
                                        r.get("state", String.class),
                                        app.truearena.engine.slay.SlayCompetition.class);
                            } catch (Exception e) {
                                throw new RuntimeException(e);
                            }
                        })
                .one()
                .block();
    }

    @Test
    void concurrentPurchasesDebitOnceAndBlocksExcludeFutureRoomsAndBallots() {
        UUID a = human(), b = human(), voter = human();
        Long before = users.coinsOf(a).block();
        var attempts =
                reactor.core.publisher.Flux.merge(
                                slay.buy(a, "female-royal").thenReturn(true).onErrorReturn(false),
                                slay.buy(a, "female-royal").thenReturn(true).onErrorReturn(false))
                        .collectList()
                        .block();
        assertThat(attempts).containsExactlyInAnyOrder(true, false);
        assertThat(users.coinsOf(a).block()).isEqualTo(before - 80);
        slay.block(a, b).block();
        UUID id =
                UUID.fromString(
                        (String)
                                slay.create(
                                                a,
                                                new SlayService.Create(
                                                        "battle", "lagos-owambe", 2, "male", false))
                                        .block()
                                        .get("id"));
        slay.join(a, id, new SlayService.Join("contestant", "female")).block();
        assertThatThrownBy(
                        () -> slay.join(b, id, new SlayService.Join("contestant", "male")).block())
                .hasMessageContaining("blocked");
        slay.join(voter, id, new SlayService.Join("contestant", "male")).block();
        slay.start(a, id).block();
        UUID look = saved(a, "female");
        slay.submit(a, id, look).block();
        slay.submit(voter, id, saved(voter, "male")).block();
        assertThat(slay.ballot(b, id).block()).isNull();
        slay.report(b, look, "Misleading submission").block();
        assertThat(
                        db.sql(
                                        "SELECT count(*) AS n FROM content_reports WHERE"
                                                + " reporter_id=:u AND subject_id=:id")
                                .bind("u", b)
                                .bind("id", look)
                                .map(r -> r.get("n", Long.class))
                                .one()
                                .block())
                .isEqualTo(1L);
        assertThatThrownBy(
                        () ->
                                slay.snapshot(
                                                a,
                                                look,
                                                Base64.getEncoder()
                                                        .encodeToString(slay.image(look).block()))
                                        .block())
                .hasMessageContaining("immutable");
    }

    @Test
    void eliminationPersistsRevealVotesAndFreshRoundsWithoutRewardingJudges() {
        List<UUID> players = java.util.stream.IntStream.range(0, 4).mapToObj(i -> human()).toList(),
                judges = java.util.stream.IntStream.range(0, 3).mapToObj(i -> human()).toList();
        UUID host = players.get(0);
        UUID id =
                UUID.fromString(
                        (String)
                                slay.create(
                                                host,
                                                new SlayService.Create(
                                                        "slay_or_pass",
                                                        "first-date",
                                                        4,
                                                        "male",
                                                        true))
                                        .block()
                                        .get("id"));
        var post =
                huud.post(
                                host,
                                new app.truearena.api.huud.HuudDtos.CreatePostRequest(
                                        "slayhuud", "Judge the style", true, 4))
                        .block();
        assertThat(post.room().id()).isEqualTo(id);
        assertThat(
                        db.sql("SELECT seats FROM huud_posts WHERE id=:id")
                                .bind("id", post.postId())
                                .map(r -> r.get("seats", Integer.class))
                                .one()
                                .block())
                .isEqualTo(10);
        for (UUID player : players)
            slay.join(player, id, new SlayService.Join("contestant", "male")).block();
        for (UUID judge : judges)
            slay.join(judge, id, new SlayService.Join("judge", "female")).block();
        slay.start(host, id).block();
        for (int round = 1; round <= 3; round++) {
            var c = state(id);
            assertThat(c.round).isEqualTo(round);
            for (var m : c.active())
                slay.submit(
                                UUID.fromString(m.userId()),
                                id,
                                saved(UUID.fromString(m.userId()), "male"))
                        .block();
            var entries = state(id).currentEntries();
            if (entries.size() > 2) {
                assertThat(
                                slay.runwayLook(
                                                judges.get(0),
                                                UUID.fromString(entries.get(0).lookId))
                                        .block())
                        .isNotNull();
                assertThatThrownBy(
                                () ->
                                        slay.runwayLook(
                                                        judges.get(0),
                                                        UUID.fromString(entries.get(1).lookId))
                                                .block())
                        .hasMessageContaining("unavailable");
            }
            if (entries.size() == 2) {
                for (UUID judge : judges) slay.finalVote(judge, id, entries.get(0).id).block();
            } else
                for (int i = 0; i < entries.size(); i++)
                    for (UUID judge : judges)
                        slay.judge(judge, id, entries.get(i).id, i < 2).block();
            if (round < 3) {
                assertThat(state(id).status).isEqualTo("round_result");
                due(id);
                slay.get(host, id).block();
            }
        }
        assertThat(state(id).status).isEqualTo("results");
        assertThat(state(id).eliminated).hasSize(2);
        for (UUID judge : judges) {
            assertThat(users.coinsOf(judge).block()).isEqualTo(200L);
            assertThat(slay.profile(judge).block().get("xp")).isEqualTo(0);
        }
        assertThat(
                        db.sql(
                                        "SELECT count(*) AS n FROM match_participants p JOIN"
                                                + " match_records m ON m.id=p.match_id WHERE"
                                                + " m.game_session_id=:id")
                                .bind("id", id)
                                .map(r -> r.get("n", Long.class))
                                .one()
                                .block())
                .isEqualTo(4L);
    }

    @Test
    void fashionCupReusesBracketAndRecordsChampionWithPrivateMatchProtection() {
        List<UUID> players = java.util.stream.IntStream.range(0, 4).mapToObj(i -> human()).toList();
        UUID host = players.get(0), outsider = human();
        var cup =
                cups.create(
                                host,
                                "Slay Test Cup",
                                4,
                                "private",
                                Instant.now().plusSeconds(3600),
                                "slayhuud")
                        .block();
        for (int i = 1; i < 4; i++) cups.join(cup.id(), players.get(i)).block();
        cups.startNow(cup.id(), host).block();
        var semis =
                db.sql(
                                "SELECT room_id FROM championship_matches WHERE championship_id=:id"
                                        + " AND round=1 ORDER BY position")
                        .bind("id", cup.id())
                        .map(r -> r.get("room_id", UUID.class))
                        .all()
                        .collectList()
                        .block();
        assertThat(semis).hasSize(2);
        for (UUID room : semis) {
            var c = state(room);
            assertThat(c.status).isEqualTo("styling");
            assertThatThrownBy(() -> slay.get(outsider, room).block())
                    .hasMessageContaining("Private");
            assertThatThrownBy(() -> slay.ballot(outsider, room).block())
                    .hasMessageContaining("Private");
            UUID winner = UUID.fromString(c.members.get(0).userId());
            slay.submit(winner, room, saved(winner, "female")).block();
            due(room);
            slay.get(winner, room).block();
        }
        UUID finalRoom =
                db.sql(
                                "SELECT room_id FROM championship_matches WHERE championship_id=:id"
                                        + " AND round=2")
                        .bind("id", cup.id())
                        .map(r -> r.get("room_id", UUID.class))
                        .one()
                        .block();
        assertThat(finalRoom).isNotNull();
        var finalState = state(finalRoom);
        UUID winner = UUID.fromString(finalState.members.get(0).userId());
        slay.submit(winner, finalRoom, saved(winner, "female")).block();
        due(finalRoom);
        slay.get(winner, finalRoom).block();
        assertThat(cups.detail(cup.id(), host).block().championId()).isEqualTo(winner);
        assertThat(slay.wardrobe(winner).block()).contains("female-champion", "male-champion");
    }

    @Test
    void noShowsAdvanceFashionCupWithoutLeavingAnActiveMatch() {
        List<UUID> players = java.util.stream.IntStream.range(0, 4).mapToObj(i -> human()).toList();
        UUID host = players.get(0);
        var cup =
                cups.create(
                                host,
                                "No Show Cup",
                                4,
                                "public",
                                Instant.now().plusSeconds(3600),
                                "slayhuud")
                        .block();
        for (int i = 1; i < 4; i++) cups.join(cup.id(), players.get(i)).block();
        cups.startNow(cup.id(), host).block();
        var rooms =
                db.sql(
                                "SELECT room_id FROM championship_matches WHERE championship_id=:id"
                                        + " AND round=1")
                        .bind("id", cup.id())
                        .map(r -> r.get("room_id", UUID.class))
                        .all()
                        .collectList()
                        .block();
        for (UUID room : rooms) {
            due(room);
            slay.get(host, room).block();
        }
        assertThat(
                        db.sql(
                                        "SELECT count(*) AS n FROM championship_matches WHERE"
                                                + " championship_id=:id AND status"
                                                + " IN('pending','active')")
                                .bind("id", cup.id())
                                .map(r -> r.get("n", Long.class))
                                .one()
                                .block())
                .isZero();
    }

    @Test
    void asynchronousChallengeAcceptsEntriesUntilServerDeadlineAndSettlesWithoutRooms() {
        UUID a = human(), b = human();
        slay.ensureScheduled().block();
        assertThat(slay.list(a).filter(v -> v.get("mode").equals("daily")).next().block())
                .isNotNull();
        UUID id = UUID.randomUUID();
        var c = new app.truearena.engine.slay.SlayCompetition();
        c.id = id.toString();
        c.mode = "daily";
        c.status = "styling";
        c.themeId = "lagos-owambe";
        c.seats = 5000;
        c.deadline = Instant.now().plusSeconds(3600);
        try {
            db.sql(
                            "INSERT INTO slay_competitions(id,mode,state,status,deadline)"
                                    + " VALUES(:id,'daily',:state,'styling',:deadline)")
                    .bind("id", id)
                    .bind("state", io.r2dbc.postgresql.codec.Json.of(json.writeValueAsString(c)))
                    .bind("deadline", c.deadline)
                    .fetch()
                    .rowsUpdated()
                    .block();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
        var challenge = slay.get(a, id).block();
        assertThat(challenge.get("roomId")).isNull();
        slay.join(a, id, new SlayService.Join("contestant", "female")).block();
        slay.join(b, id, new SlayService.Join("contestant", "male")).block();
        slay.submit(a, id, saved(a, "female")).block();
        slay.submit(b, id, saved(b, "male")).block();
        assertThat(state(id).status).isEqualTo("styling");
        due(id);
        slay.get(a, id).block();
        assertThat(state(id).status).isEqualTo("voting");
        assertThatThrownBy(() -> slay.submit(a, id, saved(a, "female")).block())
                .hasMessageContaining("closed");
        due(id);
        slay.get(a, id).block();
        assertThat(state(id).status).isEqualTo("results");
        assertThat(users.coinsOf(a).block()).isGreaterThan(200L);
    }

    @Test
    void tiedBattleRecordsDrawAndDoesNotInventTwoWins() {
        UUID a = human(), b = human();
        UUID id =
                UUID.fromString(
                        (String)
                                slay.create(
                                                a,
                                                new SlayService.Create(
                                                        "battle", "lagos-owambe", 2, "male", true))
                                        .block()
                                        .get("id"));
        slay.join(a, id, new SlayService.Join("contestant", "female")).block();
        slay.join(b, id, new SlayService.Join("contestant", "female")).block();
        slay.start(a, id).block();
        slay.submit(a, id, saved(a, "female")).block();
        slay.submit(b, id, saved(b, "female")).block();
        due(id);
        assertThat(slay.get(a, id).block().get("draw")).isEqualTo(true);
        assertThat(
                        db.sql("SELECT draw FROM match_records WHERE game_session_id=:id")
                                .bind("id", id)
                                .map(r -> r.get("draw", Boolean.class))
                                .one()
                                .block())
                .isTrue();
        assertThat(
                        db.sql(
                                        "SELECT count(*) AS n FROM match_participants p JOIN"
                                                + " match_records m ON m.id=p.match_id WHERE"
                                                + " m.game_session_id=:id AND p.outcome='won'")
                                .bind("id", id)
                                .map(r -> r.get("n", Long.class))
                                .one()
                                .block())
                .isZero();
    }
}
