package app.truearena.api.auth;

import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.ReactiveValueOperations;
import org.springframework.mock.env.MockEnvironment;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

class ReviewerOtpAccessTest {
    final ReactiveStringRedisTemplate redis = mock(ReactiveStringRedisTemplate.class);
    @SuppressWarnings("unchecked")
    final ReactiveValueOperations<String, String> values = mock(ReactiveValueOperations.class);
    final String key = "reviewer-otp-attempts:review@example.com";

    MockEnvironment configured() throws Exception {
        return new MockEnvironment()
                .withProperty("truearena.auth.reviewer-email", "review@example.com")
                .withProperty("truearena.auth.reviewer-code-sha256", HexFormat.of().formatHex(
                        MessageDigest.getInstance("SHA-256").digest("482915".getBytes(StandardCharsets.UTF_8))))
                .withProperty("truearena.auth.reviewer-expires-at", Instant.now().plusSeconds(3600).toString());
    }

    @Test void disabledByDefaultAndScopedToOneAccount() throws Exception {
        assertThat(new ReviewerOtpAccess(redis, new MockEnvironment()).owns("review@example.com")).isFalse();
        var policy = new ReviewerOtpAccess(redis, configured());
        assertThat(policy.owns(" REVIEW@example.com ")).isTrue();
        assertThat(policy.owns("someone@example.com")).isFalse();
        verifyNoInteractions(redis);
    }

    @Test void validCodeWorksWithinSharedAttemptLimit() throws Exception {
        when(redis.opsForValue()).thenReturn(values);
        when(values.increment(key)).thenReturn(Mono.just(1L));
        when(redis.expire(key, Duration.ofMinutes(15))).thenReturn(Mono.just(true));
        StepVerifier.create(new ReviewerOtpAccess(redis, configured()).verify("482915"))
                .expectNext(true).verifyComplete();
        verify(redis).expire(key, Duration.ofMinutes(15));
    }

    @Test void wrongCodeAndExhaustedAttemptsCannotLogIn() throws Exception {
        when(redis.opsForValue()).thenReturn(values);
        when(values.increment(key)).thenReturn(Mono.just(2L), Mono.just(11L));
        var policy = new ReviewerOtpAccess(redis, configured());
        StepVerifier.create(policy.verify("000000")).expectNext(false).verifyComplete();
        StepVerifier.create(policy.verify("482915")).expectNext(false).verifyComplete();
    }

    @Test void expiredOrMalformedConfigurationFailsClosed() throws Exception {
        var environment = configured().withProperty("truearena.auth.reviewer-expires-at", "invalid");
        StepVerifier.create(new ReviewerOtpAccess(redis, environment).verify("482915"))
                .expectNext(false).verifyComplete();
        environment = configured().withProperty("truearena.auth.reviewer-code-sha256", "invalid");
        StepVerifier.create(new ReviewerOtpAccess(redis, environment).verify("482915"))
                .expectNext(false).verifyComplete();
        verifyNoInteractions(redis);
    }
}
