package app.truearena.api.bot;

import reactor.core.publisher.Mono;

/**
 * Optional text communication provider. The legacy interface/method names
 * remain for provider compatibility; the runtime never uses this for moves.
 */
public interface LlmMovePicker {

    /**
     * Returns dialogue text, or empty text when unavailable. Communication
     * falls back to templates or silence; gameplay is unaffected.
     */
    Mono<String> pickMove(String systemPrompt, String userPrompt, Difficulty difficulty);
}
