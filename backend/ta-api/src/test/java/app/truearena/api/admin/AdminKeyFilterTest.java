package app.truearena.api.admin;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;

class AdminKeyFilterTest {

    private static final String REAL_KEY = "s3cret-key";

    private WebFilterChain chainThatMarks(AtomicBoolean reached) {
        return exchange -> {
            reached.set(true);
            return Mono.empty();
        };
    }

    @Test
    void nonAdminPathAlwaysPassesThroughRegardlessOfKey() {
        AdminKeyFilter filter = new AdminKeyFilter(REAL_KEY);
        var exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/api/v1/auth/otp/request"));
        AtomicBoolean reached = new AtomicBoolean(false);

        StepVerifier.create(filter.filter(exchange, chainThatMarks(reached))).verifyComplete();

        assertThat(reached).isTrue();
    }

    @Test
    void missingKeyIsRejected() {
        AdminKeyFilter filter = new AdminKeyFilter(REAL_KEY);
        var exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/api/v1/admin/overview"));
        AtomicBoolean reached = new AtomicBoolean(false);

        StepVerifier.create(filter.filter(exchange, chainThatMarks(reached))).verifyComplete();

        assertThat(reached).isFalse();
        assertThat(exchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void wrongKeyIsRejected() {
        AdminKeyFilter filter = new AdminKeyFilter(REAL_KEY);
        var exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/admin/overview").header("X-Admin-Key", "wrong"));
        AtomicBoolean reached = new AtomicBoolean(false);

        StepVerifier.create(filter.filter(exchange, chainThatMarks(reached))).verifyComplete();

        assertThat(reached).isFalse();
        assertThat(exchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void correctKeyPassesThrough() {
        AdminKeyFilter filter = new AdminKeyFilter(REAL_KEY);
        var exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/admin/overview").header("X-Admin-Key", REAL_KEY));
        AtomicBoolean reached = new AtomicBoolean(false);

        StepVerifier.create(filter.filter(exchange, chainThatMarks(reached))).verifyComplete();

        assertThat(reached).isTrue();
    }

    @Test
    void blankConfiguredKeyRejectsEverything() {
        AdminKeyFilter filter = new AdminKeyFilter("");
        var exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/admin/overview").header("X-Admin-Key", ""));
        AtomicBoolean reached = new AtomicBoolean(false);

        StepVerifier.create(filter.filter(exchange, chainThatMarks(reached))).verifyComplete();

        assertThat(reached).isFalse();
        assertThat(exchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }
}
