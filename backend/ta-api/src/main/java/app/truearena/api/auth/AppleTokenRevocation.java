package app.truearena.api.auth;

import io.jsonwebtoken.Jwts;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.web.reactive.function.BodyInserters;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.Map;

/** Exchanges a fresh, identity-verified grant and revokes it before erasure. */
@Component
public class AppleTokenRevocation {
    private final WebClient http;
    private final String clientId, teamId, keyId, privateKey;

    public AppleTokenRevocation(WebClient.Builder web,
            @Value("${truearena.auth.apple-client-id:app.truearena.truearena}") String clientId,
            @Value("${truearena.auth.apple-team-id:}") String teamId,
            @Value("${truearena.auth.apple-key-id:}") String keyId,
            @Value("${truearena.auth.apple-private-key-base64:}") String privateKey,
            @Value("${truearena.auth.apple-token-base-url:https://appleid.apple.com}") String baseUrl) {
        this.http = web.baseUrl(baseUrl).build();
        this.clientId = clientId; this.teamId = teamId; this.keyId = keyId; this.privateKey = privateKey;
    }

    public boolean configured() {
        return !teamId.isBlank() && !keyId.isBlank() && !privateKey.isBlank();
    }

    public Mono<Void> revoke(String authorizationCode, String expectedSubject) {
        return Mono.defer(() -> {
            if (!configured()) return Mono.error(new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Apple account deletion is not configured"));
            if (authorizationCode == null || authorizationCode.isBlank() || authorizationCode.length() > 4096)
                return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "Fresh Apple authorization required"));
            var tokenForm = credentials();
            tokenForm.add("code", authorizationCode);
            tokenForm.add("grant_type", "authorization_code");
            return http.post().uri("/auth/token").contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body(BodyInserters.fromFormData(tokenForm)).retrieve().bodyToMono(Map.class)
                    .flatMap(tokens -> {
                        // This ID token comes directly from Apple's authenticated HTTPS
                        // grant response, not from the caller. Bind the grant to the
                        // identity verified by AppleAuthService before revoking anything.
                        if (!grantMatches(tokens.get("id_token"), expectedSubject))
                            return Mono.error(new IllegalStateException("Apple grant identity mismatch"));
                        Object token = tokens.get("refresh_token");
                        String hint = "refresh_token";
                        if (!(token instanceof String text) || text.isBlank()) {
                            token = tokens.get("access_token"); hint = "access_token";
                        }
                        if (!(token instanceof String text) || text.isBlank())
                            return Mono.error(new IllegalStateException("Apple returned no revocable token"));
                        var form = credentials();
                        form.add("token", text); form.add("token_type_hint", hint);
                        return http.post().uri("/auth/revoke").contentType(MediaType.APPLICATION_FORM_URLENCODED)
                                .body(BodyInserters.fromFormData(form)).retrieve().bodyToMono(Void.class);
                    }).timeout(Duration.ofSeconds(20))
                    // Never expose Apple's response bodies, grant codes or tokens in API errors.
                    .onErrorMap(error -> new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                            "Apple authorization could not be revoked; your account has not been deleted"));
        });
    }

    private boolean grantMatches(Object token, String subject) {
        try {
            if (!(token instanceof String text) || subject == null || subject.isBlank()) return false;
            String[] parts=text.split("\\.");
            if (parts.length != 3) return false;
            Map<?,?> claims=new ObjectMapper().readValue(Base64.getUrlDecoder().decode(parts[1]),Map.class);
            return subject.equals(claims.get("sub"));
        } catch (Exception invalid) { return false; }
    }

    private LinkedMultiValueMap<String,String> credentials() {
        var form = new LinkedMultiValueMap<String,String>();
        form.add("client_id", clientId); form.add("client_secret", clientSecret());
        return form;
    }

    String clientSecret() {
        try {
            String pem = new String(Base64.getDecoder().decode(privateKey), StandardCharsets.US_ASCII)
                    .replace("-----BEGIN PRIVATE KEY-----", "").replace("-----END PRIVATE KEY-----", "")
                    .replaceAll("\\s", "");
            PrivateKey key = KeyFactory.getInstance("EC").generatePrivate(
                    new PKCS8EncodedKeySpec(Base64.getDecoder().decode(pem)));
            Instant now = Instant.now();
            return Jwts.builder().header().keyId(keyId).and().issuer(teamId).subject(clientId)
                    .audience().add("https://appleid.apple.com").and()
                    .issuedAt(Date.from(now)).expiration(Date.from(now.plusSeconds(300)))
                    .signWith(key, Jwts.SIG.ES256).compact();
        } catch (Exception error) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Apple account deletion is not configured");
        }
    }
}
