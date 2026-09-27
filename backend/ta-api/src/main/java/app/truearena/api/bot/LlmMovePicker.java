package app.truearena.api.bot;

import reactor.core.publisher.Mono;

/**
 * The only thing that talks to an actual model. Swappable — an
 * Anthropic-backed and an OpenAI-backed implementation can both exist as
 * beans; which one a bot uses is a config choice, not something
 * {@link BotRuntime} or any {@link GameBotAdapter} needs to know about.
 */
public interface LlmMovePicker {

    /**
     * Returns the model's raw text response (expected to contain the move as
     * JSON — each adapter defines and parses its own shape), or an empty
     * string if no real model is wired up / the call failed, in which case
     * the caller falls back to {@link GameBotAdapter#fallbackAction}.
     */
    Mono<String> pickMove(String systemPrompt, String userPrompt, Difficulty difficulty);
}
