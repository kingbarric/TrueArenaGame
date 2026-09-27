package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import org.junit.jupiter.api.Test;

import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link WordBluffBotAdapter} — verifies the documented limitation: a bot
 * describer always cycles SPIN -> REVEAL -> SKIP, never MARK_CORRECT, since
 * it cannot actually speak a description. It never acts when it isn't the
 * describer.
 */
class WordBluffBotAdapterTest {

    private static final String BOT = "bot-1";
    private static final String ALICE = "alice";

    private Map<String, Object> eventEnvelope(String type, Map<String, Object> data) {
        return Map.of("type", type, "data", data);
    }

    @Test
    void doesNothingWhenSomeoneElseIsDescribing() {
        WordBluffBotAdapter adapter = new WordBluffBotAdapter();
        adapter.onFrame("PHASE", Map.of("phase", "Turn", "round", 1), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("TURN_STARTED", Map.of("team", "A", "describer", ALICE, "round", 1)), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void doesNotPromptOffABarePhaseFrame() {
        WordBluffBotAdapter adapter = new WordBluffBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("TURN_STARTED", Map.of("team", "A", "describer", BOT, "round", 1)), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "PHASE", Map.of("phase", "Turn", "round", 1), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void spinsFirstWhenItBecomesTheBotsTurnToDescribe() {
        WordBluffBotAdapter adapter = new WordBluffBotAdapter();
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("TURN_STARTED", Map.of("team", "A", "describer", BOT, "round", 1)), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isPresent();
        // No category yet at the top of a turn, so the wheel comes first.
        assertThat(adapter.parseAction("anything", BOT).get().type()).isEqualTo("SPIN");
    }

    @Test
    void revealsAfterSpinning() {
        WordBluffBotAdapter adapter = new WordBluffBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("TURN_STARTED", Map.of("team", "A", "describer", BOT, "round", 1)), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("CATEGORY_LANDED", Map.of("category", "animals", "categoryName", "Animals")), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isPresent();
        assertThat(adapter.parseAction("anything", BOT).get().type()).isEqualTo("REVEAL");
    }

    @Test
    void alwaysSkipsAfterRevealingNeverMarksCorrect() {
        WordBluffBotAdapter adapter = new WordBluffBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("TURN_STARTED", Map.of("team", "A", "describer", BOT, "round", 1)), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("CATEGORY_LANDED", Map.of("category", "animals", "categoryName", "Animals")), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("WORD_REVEALED", Map.of("word", "elephant", "category", "animals")), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isPresent();
        Optional<PlayerAction> action = adapter.parseAction("I would say something clever here", BOT);
        assertThat(action).isPresent();
        assertThat(action.get().type()).isEqualTo("SKIP");
    }

    /**
     * The wheel is spun once a turn, so a resolved word doesn't send the
     * agent back to it — the category stays and the server puts the next
     * word up, which the agent then waits for.
     */
    @Test
    void staysOnTheSameCategoryAfterAWordResolves() {
        WordBluffBotAdapter adapter = new WordBluffBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("TURN_STARTED", Map.of("team", "A", "describer", BOT, "round", 1)), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("CATEGORY_LANDED", Map.of("category", "animals", "categoryName", "Animals")), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("WORD_REVEALED", Map.of("word", "elephant", "category", "animals")), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("WORD_RESOLVED", Map.of("result", "skipped", "word", "elephant",
                        "category", "animals", "teamAScore", 0, "teamBScore", 0)), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isPresent();
        assertThat(adapter.parseAction("anything", BOT).get().type()).isEqualTo("REVEAL");
    }

    @Test
    void doesNothingOutsideTurnPhase() {
        WordBluffBotAdapter adapter = new WordBluffBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("TURN_STARTED", Map.of("team", "A", "describer", BOT, "round", 1)), BOT, Difficulty.MEDIUM);
        adapter.onFrame("PHASE", Map.of("phase", "TurnEnd", "round", 1), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("TURN_ENDED", Map.of("team", "A", "teamAScore", 0, "teamBScore", 0)), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void doesNothingOnceTheGameIsOver() {
        WordBluffBotAdapter adapter = new WordBluffBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("TURN_STARTED", Map.of("team", "A", "describer", BOT, "round", 1)), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("GAME_OVER", Map.of("outcome", Map.of())), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("CATEGORY_LANDED", Map.of("category", "animals", "categoryName", "Animals")), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void ignoresTheModelsResponseContentEntirely() {
        WordBluffBotAdapter adapter = new WordBluffBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("TURN_STARTED", Map.of("team", "A", "describer", BOT, "round", 1)), BOT, Difficulty.MEDIUM);
        assertThat(adapter.parseAction("garbage that is not JSON at all", BOT).get().type()).isEqualTo("SPIN");
        assertThat(adapter.parseAction(null, BOT).get().type()).isEqualTo("SPIN");
        assertThat(adapter.parseAction("", BOT).get().type()).isEqualTo("SPIN");
    }

    @Test
    void fallbackMatchesParseAction() {
        WordBluffBotAdapter adapter = new WordBluffBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("TURN_STARTED", Map.of("team", "A", "describer", BOT, "round", 1)), BOT, Difficulty.MEDIUM);
        assertThat(adapter.fallbackAction(BOT).get().type()).isEqualTo("SPIN");
    }
}
