package app.truearena.api.bot;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.List;
import java.util.Map;

/**
 * Calls Groq's OpenAI-compatible chat completions endpoint
 * (console.groq.com — free tier, no card required as of writing). Only
 * registered as the active {@link LlmMovePicker} bean when
 * {@code groq.api.key} is actually set — see {@code BotLlmConfig} — so
 * leaving it unset keeps every bot on {@link StubMovePicker}'s
 * random-legal-move fallback rather than failing outright.
 */
public final class GroqMovePicker implements LlmMovePicker {

    private static final Logger log = LoggerFactory.getLogger(GroqMovePicker.class);
    private static final String URL = "https://api.groq.com/openai/v1/chat/completions";

    private final WebClient client;
    private final String apiKey;

    public GroqMovePicker(WebClient client, String apiKey) {
        this.client = client;
        this.apiKey = apiKey;
    }

    @Override
    public Mono<String> pickMove(String systemPrompt, String userPrompt, Difficulty difficulty) {
        String model = switch (difficulty) {
            case EASY, MEDIUM -> "llama-3.1-8b-instant";
            case HARD -> "llama-3.3-70b-versatile";
        };
        double temperature = difficulty == Difficulty.EASY ? 0.9 : 0.2;

        Map<String, Object> body = Map.of(
                "model", model,
                "messages", List.of(
                        Map.of("role", "system", "content", systemPrompt),
                        Map.of("role", "user", "content", userPrompt)),
                "temperature", temperature,
                "max_tokens", 60);

        return client.post()
                .uri(URL)
                .header("Authorization", "Bearer " + apiKey)
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(body)
                .retrieve()
                .bodyToMono(Map.class)
                .map(this::extractContent)
                .timeout(Duration.ofSeconds(10))
                .onErrorResume(e -> {
                    log.warn("Groq call failed, bot will fall back to a random legal move: {}", e.toString());
                    return Mono.just("");
                });
    }

    @SuppressWarnings("unchecked")
    private String extractContent(Map<?, ?> response) {
        try {
            List<?> choices = (List<?>) response.get("choices");
            Map<?, ?> first = (Map<?, ?>) choices.get(0);
            Map<?, ?> message = (Map<?, ?>) first.get("message");
            return String.valueOf(message.get("content"));
        } catch (Exception e) {
            log.warn("Unexpected Groq response shape: {}", response);
            return "";
        }
    }
}
