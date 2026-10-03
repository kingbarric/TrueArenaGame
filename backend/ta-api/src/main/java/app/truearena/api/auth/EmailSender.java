package app.truearena.api.auth;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientRequestException;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeoutException;

/** Sends email verification codes through Brevo's transactional email API. */
@Component
public class EmailSender {

    private static final Logger log = LoggerFactory.getLogger(EmailSender.class);
    private static final Duration SEND_TIMEOUT = Duration.ofSeconds(10);

    private final WebClient client;
    private final String apiKey;
    private final String senderAddress;
    private final String apiUrl;
    private final boolean local;

    public EmailSender(WebClient.Builder webClient, Environment environment,
                       @Value("${truearena.email.brevo-api-key:}") String apiKey,
                       @Value("${truearena.email.sender-address:verify@playhuud.com}") String senderAddress,
                       @Value("${truearena.email.brevo-api-url:https://api.brevo.com/v3/smtp/email}") String apiUrl) {
        this.client = webClient.build();
        this.apiKey = apiKey;
        this.senderAddress = senderAddress;
        this.apiUrl = apiUrl;
        this.local = environment.acceptsProfiles(Profiles.of("local"));
    }

    public Mono<Void> send(String email, String code) {
        if (apiKey.isBlank()) {
            if (local) {
                return Mono.fromRunnable(() -> log.info("[EMAIL-STUB] OTP for {} = {}", email, code));
            }
            return Mono.error(new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Email verification is not configured"));
        }

        return client.post()
                .uri(apiUrl)
                .header("api-key", apiKey)
                .bodyValue(Map.of(
                        "sender", Map.of("email", senderAddress, "name", "PlayHuud"),
                        "to", List.of(Map.of("email", email)),
                        "subject", "Your PlayHuud verification code",
                        "textContent", "Your PlayHuud verification code is " + code
                                + ". It expires in 5 minutes. If you did not request this, ignore this email."))
                .retrieve()
                .onStatus(status -> status.isError(), response -> {
                    log.warn("Brevo rejected verification email with HTTP {}", response.statusCode().value());
                    return Mono.error(deliveryFailure());
                })
                .bodyToMono(Void.class)
                .timeout(SEND_TIMEOUT)
                .onErrorMap(error -> error instanceof WebClientRequestException || error instanceof TimeoutException,
                        error -> deliveryFailure());
    }

    private static ResponseStatusException deliveryFailure() {
        return new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "Could not send verification email. Please try again.");
    }
}
