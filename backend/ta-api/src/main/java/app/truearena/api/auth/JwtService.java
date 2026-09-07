package app.truearena.api.auth;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

@Service
public class JwtService {

    private final SecretKey key;
    private final Duration accessTtl;
    private final Duration refreshTtl;

    public JwtService(
            @Value("${truearena.auth.jwt-secret}") String secret,
            @Value("${truearena.auth.access-ttl:15m}") Duration accessTtl,
            @Value("${truearena.auth.refresh-ttl:30d}") Duration refreshTtl) {
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.accessTtl = accessTtl;
        this.refreshTtl = refreshTtl;
    }

    public String issueAccess(UUID userId) {
        return build(userId, "access", accessTtl);
    }

    public String issueRefresh(UUID userId) {
        return build(userId, "refresh", refreshTtl);
    }

    public long accessTtlSeconds() {
        return accessTtl.toSeconds();
    }

    public UUID parseAccess(String token) {
        return parse(token, "access");
    }

    public UUID parseRefresh(String token) {
        return parse(token, "refresh");
    }

    private String build(UUID userId, String type, Duration ttl) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(userId.toString())
                .claim("typ", type)
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(ttl)))
                .signWith(key)
                .compact();
    }

    private UUID parse(String token, String expectedType) {
        Claims c = Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload();
        if (!expectedType.equals(c.get("typ", String.class))) {
            throw new IllegalArgumentException("wrong token type");
        }
        return UUID.fromString(c.getSubject());
    }
}
