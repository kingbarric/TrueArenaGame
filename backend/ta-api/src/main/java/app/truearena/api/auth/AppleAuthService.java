package app.truearena.api.auth;

import app.truearena.api.support.ApiExceptions;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.math.BigInteger;
import java.security.KeyFactory;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAPublicKeySpec;
import java.time.Duration;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Verifies native iOS Apple ID tokens against Apple's published signing keys. */
@Service
public class AppleAuthService {
    private static final Duration NONCE_TTL = Duration.ofMinutes(5);
    private static final String NONCE_PREFIX = "auth:apple:nonce:";
    private final ReactiveStringRedisTemplate redis;
    private final WebClient apple = WebClient.create("https://appleid.apple.com");
    private final ObjectMapper json = new ObjectMapper();
    private final String clientId;

    public AppleAuthService(ReactiveStringRedisTemplate redis,
                            @Value("${truearena.auth.apple-client-id:}") String clientId) {
        this.redis = redis;
        this.clientId = clientId;
    }

    public record AppleIdentity(String subject, String email) {
    }

    public Mono<String> challenge() {
        String nonce = UUID.randomUUID().toString();
        return redis.opsForValue().set(NONCE_PREFIX + nonce, "1", NONCE_TTL)
                .flatMap(saved -> saved ? Mono.just(nonce) : Mono.error(ApiExceptions.badRequest("Could not start Apple sign-in")));
    }

    public Mono<AppleIdentity> verify(String idToken, String nonce) {
        if (clientId == null || clientId.isBlank()) {
            return Mono.error(ApiExceptions.badRequest("Apple sign-in is not configured"));
        }
        if (idToken == null || idToken.isBlank() || idToken.length() > 16000
                || nonce == null || !nonce.matches("[0-9a-f-]{36}")) {
            return Mono.error(ApiExceptions.unauthorized("invalid Apple token"));
        }
        return apple.get().uri("/auth/keys").retrieve().bodyToMono(Map.class)
                .map(keys -> verifiedIdentity(idToken, nonce, clientId, keys, json))
                .onErrorMap(e -> e instanceof org.springframework.web.server.ResponseStatusException
                        ? e : ApiExceptions.unauthorized("invalid Apple token"))
                .flatMap(identity -> redis.opsForValue().getAndDelete(NONCE_PREFIX + nonce)
                        .filter("1"::equals)
                        .map(ignored -> identity)
                        .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("Apple sign-in challenge expired"))));
    }

    /** Package-visible so signature, audience and nonce checks can be tested with local keys. */
    static AppleIdentity verifiedIdentity(String token, String nonce, String clientId,
                                          Map<?, ?> jwks, ObjectMapper json) {
        try {
            String[] parts = token.split("\\.");
            if (parts.length != 3) throw new IllegalArgumentException("malformed token");
            Map<String, Object> header = json.readValue(
                    Base64.getUrlDecoder().decode(parts[0]), new TypeReference<>() {});
            if (!"RS256".equals(header.get("alg")) || !(header.get("kid") instanceof String kid)) {
                throw new IllegalArgumentException("unsupported token header");
            }
            RSAPublicKey key = keyFor(kid, jwks);
            Claims claims = Jwts.parser().verifyWith(key).build()
                    .parseSignedClaims(token).getPayload();
            if (!"https://appleid.apple.com".equals(claims.getIssuer())
                    || claims.getAudience() == null || !claims.getAudience().contains(clientId)
                    || claims.getExpiration() == null
                    || !nonce.equals(claims.get("nonce", String.class))
                    || claims.getSubject() == null || claims.getSubject().isBlank()) {
                throw new IllegalArgumentException("wrong Apple token claims");
            }
            String email = claims.get("email", String.class);
            Object verified = claims.get("email_verified");
            if (email != null && !Boolean.TRUE.equals(verified) && !"true".equals(verified)) {
                throw new IllegalArgumentException("unverified Apple email");
            }
            return new AppleIdentity(claims.getSubject(), email);
        } catch (Exception e) {
            throw ApiExceptions.unauthorized("invalid Apple token");
        }
    }

    private static RSAPublicKey keyFor(String kid, Map<?, ?> jwks) throws Exception {
        if (!(jwks.get("keys") instanceof List<?> keys)) {
            throw new IllegalArgumentException("missing Apple keys");
        }
        for (Object item : keys) {
            if (!(item instanceof Map<?, ?> key) || !kid.equals(key.get("kid"))
                    || !"RSA".equals(key.get("kty")) || !"RS256".equals(key.get("alg"))) {
                continue;
            }
            byte[] modulus = Base64.getUrlDecoder().decode((String) key.get("n"));
            byte[] exponent = Base64.getUrlDecoder().decode((String) key.get("e"));
            return (RSAPublicKey) KeyFactory.getInstance("RSA").generatePublic(
                    new RSAPublicKeySpec(new BigInteger(1, modulus), new BigInteger(1, exponent)));
        }
        throw new IllegalArgumentException("unknown Apple signing key");
    }
}
