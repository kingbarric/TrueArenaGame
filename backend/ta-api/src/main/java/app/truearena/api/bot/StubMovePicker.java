package app.truearena.api.bot;

import reactor.core.publisher.Mono;

/**
 * The fallback bean when no real LLM key is configured — see
 * {@code BotLlmConfig} for how {@link GroqMovePicker} takes over instead
 * once {@code groq.api.key} is set, and docs/DEV_REFERENCE.md for the
 * free-tier setup. Always "fails" (empty response), which routes every bot
 * move through {@link GameBotAdapter#fallbackAction} instead — so the whole
 * bot pipeline (add bot, connect, react to turns, send actions) is
 * exercisable and testable without any API key at all.
 */
public class StubMovePicker implements LlmMovePicker {

    @Override
    public Mono<String> pickMove(String systemPrompt, String userPrompt, Difficulty difficulty) {
        return Mono.just("");
    }
}
