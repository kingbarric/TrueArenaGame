package app.truearena.api.bot;

import reactor.core.publisher.Mono;

/** No communication provider configured: templates remain available; gameplay is always local. */
public class StubMovePicker implements LlmMovePicker {

    @Override
    public Mono<String> pickMove(String systemPrompt, String userPrompt, Difficulty difficulty) {
        return Mono.just("");
    }
}
