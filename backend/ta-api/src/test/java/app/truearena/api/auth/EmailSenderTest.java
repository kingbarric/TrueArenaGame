package app.truearena.api.auth;

import io.netty.handler.codec.http.HttpResponseStatus;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.netty.DisposableServer;
import reactor.netty.http.server.HttpServer;
import reactor.test.StepVerifier;

import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

class EmailSenderTest {

    private DisposableServer server;

    @AfterEach
    void stopServer() {
        if (server != null) server.disposeNow();
    }

    @Test
    void sendsVerificationCodeThroughBrevoWithConfiguredSender() {
        AtomicReference<String> apiKey = new AtomicReference<>();
        AtomicReference<String> body = new AtomicReference<>();
        server = HttpServer.create().host("127.0.0.1").port(0)
                .route(routes -> routes.post("/v3/smtp/email", (request, response) -> {
                    apiKey.set(request.requestHeaders().get("api-key"));
                    return request.receive().aggregate().asString()
                            .flatMap(content -> {
                                body.set(content);
                                return response.status(HttpResponseStatus.CREATED)
                                        .sendString(Mono.just("{\"messageId\":\"test-id\"}"))
                                        .then();
                            });
                })).bindNow();

        StepVerifier.create(sender("test-key").send("player@example.com", "123456"))
                .verifyComplete();

        assertThat(apiKey.get()).isEqualTo("test-key");
        assertThat(body.get()).contains("verify@playhuud.com", "player@example.com", "123456",
                "Your PlayHuud verification code");
    }

    @Test
    void doesNotClaimDeliveryWhenBrevoRejectsTheRequest() {
        server = HttpServer.create().host("127.0.0.1").port(0)
                .route(routes -> routes.post("/v3/smtp/email", (request, response) ->
                        response.status(HttpResponseStatus.UNAUTHORIZED).send()))
                .bindNow();

        StepVerifier.create(sender("invalid-key").send("player@example.com", "123456"))
                .expectErrorMatches(error -> error instanceof ResponseStatusException response
                        && response.getStatusCode() == HttpStatus.BAD_GATEWAY)
                .verify();
    }

    @Test
    void refusesToPretendEmailWasSentWithoutAnApiKeyOutsideLocalDevelopment() {
        StepVerifier.create(sender("").send("player@example.com", "123456"))
                .expectErrorMatches(error -> error instanceof ResponseStatusException response
                        && response.getStatusCode() == HttpStatus.SERVICE_UNAVAILABLE)
                .verify();
    }

    private EmailSender sender(String key) {
        String url = server == null ? "http://127.0.0.1:1/v3/smtp/email"
                : "http://127.0.0.1:" + server.port() + "/v3/smtp/email";
        return new EmailSender(WebClient.builder(), new MockEnvironment(), key,
                "verify@playhuud.com", url);
    }
}
