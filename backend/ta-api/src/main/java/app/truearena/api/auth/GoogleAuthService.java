package app.truearena.api.auth;

import app.truearena.api.support.ApiExceptions;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

/**
 * Verifies a Google Sign-In ID token by asking Google itself, rather than pulling in
 * a JWKS/crypto library — {@code tokeninfo} is a supported, documented endpoint for
 * exactly this (Google's own guidance calls it fine for low-volume server-side
 * verification; a JWKS-based local check would be the move if this needs to scale up).
 *
 * <p>{@code truearena.auth.google-client-id} must be the app's **Web** OAuth client ID
 * — set it as {@code serverClientId} in the Flutter app's {@code GoogleSignIn(...)} too,
 * so the ID token's {@code aud} actually matches what this checks. See
 * docs/DEV_REFERENCE.md for the full Google Cloud Console setup this depends on.
 */
@Service
public class GoogleAuthService {

    private final WebClient http = WebClient.create("https://oauth2.googleapis.com");
    private final List<String> allowedAudiences;

    public GoogleAuthService(@Value("${truearena.auth.google-client-id:}") String clientId) {
        this.allowedAudiences = clientId == null || clientId.isBlank() ? List.of()
                : Arrays.stream(clientId.split(",")).map(String::trim).filter(s -> !s.isBlank()).toList();
    }

    public record GoogleIdentity(String subject, String email, String name) {
    }

    public Mono<GoogleIdentity> verify(String idToken) {
        if (allowedAudiences.isEmpty()) {
            return Mono.error(ApiExceptions.badRequest("Google sign-in isn't configured on this server yet"));
        }
        if (idToken == null || idToken.isBlank()) {
            return Mono.error(ApiExceptions.badRequest("idToken is required"));
        }
        return http.get()
                .uri("/tokeninfo?id_token={t}", idToken)
                .retrieve()
                .onStatus(s -> s.value() == 400, r -> Mono.error(ApiExceptions.unauthorized("invalid Google token")))
                .bodyToMono(Map.class)
                .flatMap(body -> {
                    String aud = String.valueOf(body.get("aud"));
                    String emailVerified = String.valueOf(body.get("email_verified"));
                    String email = (String) body.get("email");
                    String subject = (String) body.get("sub");
                    if (!allowedAudiences.contains(aud)) {
                        return Mono.error(ApiExceptions.unauthorized("token was not issued for this app"));
                    }
                    if (!"true".equals(emailVerified) || email == null || email.isBlank()
                            || subject == null || subject.isBlank()) {
                        return Mono.error(ApiExceptions.unauthorized("Google account has no verified email"));
                    }
                    return Mono.just(new GoogleIdentity(subject, email, (String) body.get("name")));
                });
    }
}
