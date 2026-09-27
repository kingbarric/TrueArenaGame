package app.truearena.api.bot;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.util.retry.Retry;

import java.time.Duration;
import java.util.List;
import java.util.Map;

/**
 * Calls Google's Gemini {@code generateContent} endpoint. Same contract as
 * {@link GroqMovePicker} — one prompt in, the model's raw text out, an empty
 * string on any failure so the caller falls back to a legal move rather than
 * the game stalling on a flaky network call.
 *
 * <p>Gemini's API differs from the OpenAI-compatible shape in two ways worth
 * noting: the system prompt goes in its own {@code system_instruction} field
 * rather than a message with {@code role: "system"}, and the key travels as
 * an {@code x-goog-api-key} header rather than a bearer token.
 *
 * <p>Only registered when {@code gemini.api.key} (env {@code GEMINI_API_KEY})
 * is set — see {@link BotLlmConfig}. The key is never held in source or
 * committed config; it is read from the environment at startup.
 */
public final class GeminiMovePicker implements LlmMovePicker {

    private static final Logger log = LoggerFactory.getLogger(GeminiMovePicker.class);
    private static final String BASE = "https://generativelanguage.googleapis.com/v1beta/models/";

    private final WebClient client;
    private final String apiKey;

    public GeminiMovePicker(WebClient client, String apiKey) {
        this.client = client;
        this.apiKey = apiKey;
    }

    @Override
    public Mono<String> pickMove(String systemPrompt, String userPrompt, Difficulty difficulty) {
        // Deliberately the floating "-latest" aliases, not pinned versions:
        // a pinned gemini-2.0-flash here was already retired server-side and
        // returned 404, which would have silently dropped every agent back to
        // random moves. These aliases track forward on their own.
        String model = switch (difficulty) {
            case EASY, MEDIUM -> "gemini-flash-lite-latest";
            case HARD -> "gemini-flash-latest";
        };
        double temperature = difficulty == Difficulty.EASY ? 0.9 : 0.2;

        Map<String, Object> body = Map.of(
                "system_instruction", Map.of("parts", List.of(Map.of("text", systemPrompt))),
                "contents", List.of(Map.of(
                        "role", "user",
                        "parts", List.of(Map.of("text", userPrompt)))),
                "generationConfig", Map.of(
                        "temperature", temperature,
                        // Enough for a move token or a one-line clue, not an essay.
                        "maxOutputTokens", 200));

        return client.post()
                .uri(BASE + model + ":generateContent")
                .header("x-goog-api-key", apiKey)
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(body)
                .retrieve()
                .bodyToMono(Map.class)
                .map(this::extractText)
                .timeout(Duration.ofSeconds(10))
                // 503/429 from a shared model endpoint is routine, not a real
                // failure — observed on the very first live game. Without a
                // retry the agent silently drops to a random legal move and
                // looks like it isn't thinking. Two quick attempts convert
                // most of those back into an actual decision; anything still
                // failing falls through to the legal-move safety net below.
                .retryWhen(Retry.backoff(2, Duration.ofMillis(400))
                        .filter(GeminiMovePicker::isTransient)
                        .transientErrors(true))
                .onErrorResume(e -> {
                    log.warn("Gemini call failed, bot will fall back to a legal move: {}", e.toString());
                    return Mono.just("");
                });
    }

    private static boolean isTransient(Throwable e) {
        if (e instanceof WebClientResponseException w) {
            int code = w.getStatusCode().value();
            return code == 429 || code == 500 || code == 502 || code == 503 || code == 504;
        }
        // a timeout or a dropped connection is worth one more shot too
        return e instanceof java.util.concurrent.TimeoutException
                || e instanceof java.io.IOException;
    }

    private String extractText(Map<?, ?> response) {
        try {
            List<?> candidates = (List<?>) response.get("candidates");
            Map<?, ?> first = (Map<?, ?>) candidates.get(0);
            Map<?, ?> content = (Map<?, ?>) first.get("content");
            List<?> parts = (List<?>) content.get("parts");
            StringBuilder out = new StringBuilder();
            for (Object part : parts) {
                Object text = ((Map<?, ?>) part).get("text");
                if (text != null) {
                    out.append(text);
                }
            }
            return out.toString().trim();
        } catch (Exception e) {
            // A safety block or quota rejection lands here too — log the shape
            // once and fall back, rather than throwing inside a game turn.
            log.warn("Unexpected Gemini response shape: {}", response);
            return "";
        }
    }
}
