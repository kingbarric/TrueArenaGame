package app.truearena;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Phase 0.1 smoke: the application context wires with no infrastructure attached.
 * Data/Redis/Flyway autoconfig is excluded here; full wiring is covered by
 * {@code ./gradlew integrationTest} once Phase 1+ lands.
 */
@SpringBootTest(properties = {
        "spring.autoconfigure.exclude="
                + "org.springframework.boot.autoconfigure.r2dbc.R2dbcAutoConfiguration,"
                + "org.springframework.boot.autoconfigure.data.r2dbc.R2dbcDataAutoConfiguration,"
                + "org.springframework.boot.autoconfigure.data.redis.RedisAutoConfiguration,"
                + "org.springframework.boot.autoconfigure.data.redis.RedisReactiveAutoConfiguration,"
                + "org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration"
})
class ContextLoadsTest {

    @Test
    void contextLoads() {
        // Fails the build if the bean graph is broken.
    }
}
