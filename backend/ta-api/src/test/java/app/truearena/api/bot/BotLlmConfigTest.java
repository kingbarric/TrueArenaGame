package app.truearena.api.bot;

import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.function.client.WebClient;
import static org.assertj.core.api.Assertions.assertThat;

class BotLlmConfigTest {
    @Test void blankKeysUseTheOfflineFallbackAndGroqIsNotShadowedByBlankGemini() {
        var config = new BotLlmConfig();
        assertThat(config.movePicker(WebClient.builder(), "", "")).isInstanceOf(StubMovePicker.class);
        assertThat(config.movePicker(WebClient.builder(), " ", "configured-key")).isInstanceOf(GroqMovePicker.class);
        assertThat(config.movePicker(WebClient.builder(), "configured-key", "configured-key")).isInstanceOf(GeminiMovePicker.class);
    }
}
