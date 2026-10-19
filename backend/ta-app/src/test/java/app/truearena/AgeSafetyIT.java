package app.truearena;
import app.truearena.api.auth.*;
import app.truearena.api.safety.AgeSafetyService;
import app.truearena.persistence.*;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.junit.jupiter.api.*;
import java.util.UUID;
import java.util.Map;
import java.time.Duration;
import static org.assertj.core.api.Assertions.*;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
@Tag("integration") @ActiveProfiles("test")
class AgeSafetyIT {
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
        r.add("truearena.safety.age-enforcement-enabled", () -> "true");
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

    @Autowired UserRepository users;
    @Autowired DatabaseClient db;
    @Autowired JwtService jwt;
    @Autowired AccountSessionGuard sessions;
    @LocalServerPort int port;
    private WebTestClient client() { return WebTestClient.bindToServer().baseUrl("http://localhost:"+port)
            .responseTimeout(Duration.ofSeconds(15)).build(); }
    private UserRow guest() { String id=UUID.randomUUID().toString();
        return users.save(UserRow.newGuest("age-it-"+id,"Age test", "age_"+id.replace("-", ""))).block(); }
    private String bearer(UserRow u) { return "Bearer "+jwt.issueAccess(u.id()); }
    private void declare(UserRow u,String band) {
        client().put().uri("/api/v1/me/age-safety").header("Authorization",bearer(u))
                .bodyValue(Map.of("ageBand",band,"countryCode","GB","noticeAcknowledged",true))
                .exchange().expectStatus().isOk();
    }
    @Test void guestsCannotBypassAgeChecksThroughHttpOrSockets() {
        var u=guest();
        client().get().uri("/api/v1/me/wallet").header("Authorization",bearer(u)).exchange().expectStatus().isForbidden();
        client().get().uri("/api/v1/me/age-safety").header("Authorization",bearer(u)).exchange().expectStatus().isOk()
                .expectBody().jsonPath("$.declarationRequired").isEqualTo(true).jsonPath("$.canAccess").isEqualTo(false);
        assertThatThrownBy(()->sessions.require(u.id()).block()).hasMessageContaining("AGE_DECLARATION_REQUIRED");
        assertThatThrownBy(()->sessions.requireRoomParticipant(u.id()).block()).hasMessageContaining("AGE_DECLARATION_REQUIRED");
    }
    @Test void everyMinorBandIsRestrictedButRecoveryAndDeletionRemainReachable() {
        for(String band:new String[]{"UNDER_13","AGE_13_15","AGE_16_17"}) {
            var u=guest();declare(u,band);
            client().get().uri("/api/v1/me/wallet").header("Authorization",bearer(u)).exchange().expectStatus().isForbidden();
            client().get().uri("/api/v1/huud/feed").header("Authorization",bearer(u)).exchange().expectStatus().isForbidden();
            client().get().uri("/api/v1/me/account/deletion-requirements").header("Authorization",bearer(u)).exchange().expectStatus().isOk();
            client().delete().uri("/api/v1/me/account").header("Authorization",bearer(u))
                .exchange().expectStatus().isBadRequest(); // no confirmation body; the age guard must not return 403
        }
    }
    @Test void adultCanProceedAndAgeDetailsAreNotInPublicOrAuthUserDtos() {
        var u=guest();declare(u,"ADULT");
        client().get().uri("/api/v1/me/wallet").header("Authorization",bearer(u)).exchange().expectStatus().isOk();
        client().get().uri("/api/v1/me").header("Authorization",bearer(u)).exchange().expectStatus().isOk()
                .expectBody().jsonPath("$.ageBand").doesNotExist().jsonPath("$.countryCode").doesNotExist();
        assertThatCode(()->sessions.require(u.id()).block()).doesNotThrowAnyException();
    }
    @Test void declarationIsImmutableAndCannotTargetAnotherUser() {
        var u=guest();var other=guest();declare(u,"AGE_13_15");
        client().put().uri("/api/v1/me/age-safety").header("Authorization",bearer(u))
            .bodyValue(Map.of("ageBand","ADULT","countryCode","GB","noticeAcknowledged",true,"userId",other.id()))
            .exchange().expectStatus().isEqualTo(409);
        client().get().uri("/api/v1/me/age-safety").header("Authorization",bearer(u)).exchange()
            .expectStatus().isOk().expectBody().jsonPath("$.ageBand").isEqualTo("AGE_13_15");
        client().get().uri("/api/v1/me/age-safety").header("Authorization",bearer(other)).exchange()
            .expectStatus().isOk().expectBody().jsonPath("$.declarationRequired").isEqualTo(true);
    }
    @Test void unauthenticatedCallerCannotReadOrWriteAgeDetails() {
        client().get().uri("/api/v1/me/age-safety").exchange().expectStatus().isUnauthorized();
        client().put().uri("/api/v1/me/age-safety").bodyValue(Map.of("ageBand","ADULT","countryCode","GB","noticeAcknowledged",true))
            .exchange().expectStatus().isUnauthorized();
    }
}
