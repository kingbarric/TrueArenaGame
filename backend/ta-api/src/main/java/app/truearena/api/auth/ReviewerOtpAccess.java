package app.truearena.api.auth;

import org.springframework.core.env.Environment;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Locale;

/** Optional, expiring access to one dedicated store-review account. Never a global OTP bypass. */
final class ReviewerOtpAccess {
    private final ReactiveStringRedisTemplate redis;
    private final String email;
    private final String hash;
    private final Instant expiresAt;

    ReviewerOtpAccess(ReactiveStringRedisTemplate redis, Environment environment) {
        this.redis = redis;
        email = normalize(environment.getProperty("truearena.auth.reviewer-email", ""));
        hash = environment.getProperty("truearena.auth.reviewer-code-sha256", "");
        Instant expiry;
        try {
            expiry = Instant.parse(environment.getProperty("truearena.auth.reviewer-expires-at", ""));
        } catch (java.time.format.DateTimeParseException e) {
            expiry = Instant.EPOCH;
        }
        expiresAt = expiry;
    }

    boolean owns(String identifier) {
        return !email.isBlank() && email.equals(normalize(identifier));
    }

    Mono<Boolean> verify(String code) {
        if (!expiresAt.isAfter(Instant.now()) || !hash.matches("[0-9a-fA-F]{64}")) return Mono.just(false);
        String key = "reviewer-otp-attempts:" + email;
        // Shared Redis limit across server instances; failures of the limiter fail closed.
        return redis.opsForValue().increment(key).flatMap(count -> {
            Mono<Boolean> ttl = count == 1 ? redis.expire(key, Duration.ofMinutes(15)) : Mono.just(true);
            return ttl.map(ok -> ok && count <= 10 && matches(code));
        });
    }

    private boolean matches(String code) {
        if (code == null || !code.matches("[0-9]{6}")) return false;
        try {
            byte[] actual = MessageDigest.getInstance("SHA-256").digest(code.getBytes(StandardCharsets.UTF_8));
            return MessageDigest.isEqual(HexFormat.of().parseHex(hash), actual);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
    }
}
