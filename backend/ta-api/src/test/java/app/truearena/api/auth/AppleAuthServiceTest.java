package app.truearena.api.auth;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Jwts;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigInteger;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class AppleAuthServiceTest {
    private static final String CLIENT_ID = "app.truearena.truearena";
    private static final String NONCE = "bb0d0d80-6140-4e74-b7eb-b656230ea79e";
    private final ObjectMapper json = new ObjectMapper();

    @Test
    void acceptsOnlyAppleSignedTokenForThisAppAndChallenge() throws Exception {
        KeyPair pair = rsa();
        Map<String, Object> keys = keys(pair);
        String token = token(pair, CLIENT_ID, NONCE);

        assertThat(AppleAuthService.verifiedIdentity(token, NONCE, CLIENT_ID, keys, json))
                .isEqualTo(new AppleAuthService.AppleIdentity("apple-user", "person@example.com"));
        assertThatThrownBy(() -> AppleAuthService.verifiedIdentity(token, "wrong", CLIENT_ID, keys, json))
                .isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> AppleAuthService.verifiedIdentity(token, NONCE, "another.app", keys, json))
                .isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> AppleAuthService.verifiedIdentity(token(pair, CLIENT_ID, NONCE),
                NONCE, CLIENT_ID, keys(rsa()), json))
                .isInstanceOf(ResponseStatusException.class);
    }

    private static KeyPair rsa() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        return generator.generateKeyPair();
    }

    private static String token(KeyPair pair, String audience, String nonce) {
        return Jwts.builder()
                .header().keyId("test-key").and()
                .issuer("https://appleid.apple.com")
                .audience().add(audience).and()
                .subject("apple-user")
                .claim("nonce", nonce)
                .claim("email", "person@example.com")
                .claim("email_verified", "true")
                .expiration(Date.from(Instant.now().plusSeconds(300)))
                .signWith(pair.getPrivate(), Jwts.SIG.RS256)
                .compact();
    }

    private static Map<String, Object> keys(KeyPair pair) {
        RSAPublicKey key = (RSAPublicKey) pair.getPublic();
        return Map.of("keys", List.of(Map.of(
                "kid", "test-key", "kty", "RSA", "alg", "RS256",
                "n", encoded(key.getModulus()), "e", encoded(key.getPublicExponent()))));
    }

    private static String encoded(BigInteger value) {
        byte[] bytes = value.toByteArray();
        if (bytes[0] == 0) bytes = java.util.Arrays.copyOfRange(bytes, 1, bytes.length);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}
