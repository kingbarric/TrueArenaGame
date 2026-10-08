package app.truearena.api.bot;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.client.WebClient;

/**
 * Picks which {@link LlmMovePicker} bean is active, in order:
 *
 * <ol>
 *   <li>{@link GeminiMovePicker} when {@code gemini.api.key}
 *       (env {@code GEMINI_API_KEY}) is set — preferred, and what the Cyber
 *       Agents run on.</li>
 *   <li>{@link GroqMovePicker} when {@code groq.api.key}
 *       (env {@code GROQ_API_KEY}) is set.</li>
 *   <li>{@link StubMovePicker}'s random-legal-move fallback otherwise, so a
 *       machine with no key configured still runs playable bots.</li>
 * </ol>
 *
 * Keys are read from the environment only — never checked into source or
 * committed config. See docs/DEV_REFERENCE.md.
 */
@Configuration
public class BotLlmConfig {

    @Bean
    @ConditionalOnMissingBean(LlmMovePicker.class)
    public LlmMovePicker movePicker(WebClient.Builder builder,
            @Value("${gemini.api.key:}") String geminiKey,
            @Value("${groq.api.key:}") String groqKey) {
        if (!geminiKey.isBlank()) return new GeminiMovePicker(builder.build(), geminiKey);
        if (!groqKey.isBlank()) return new GroqMovePicker(builder.build(), groqKey);
        return new StubMovePicker();
    }
}
