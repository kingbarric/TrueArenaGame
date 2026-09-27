package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link DraughtsBotAdapter} driven with the exact frame shapes
 * {@code GameOrchestrator}/{@code DraughtsModule} actually send (see
 * {@code eventEnvelope}/{@code commonView}) — a mismatch there would mean
 * the bot silently never acts, which is exactly the failure mode this
 * guards against.
 */
class DraughtsBotAdapterTest {

    private static final String PLAYER_A = "alice";
    private static final String PLAYER_B = "bot-1";

    private List<Object> startingBoard() {
        List<Object> board = new ArrayList<>();
        for (int i = 0; i < 20; i++) board.add("A_MAN");
        for (int i = 0; i < 10; i++) board.add(null);
        for (int i = 0; i < 20; i++) board.add("B_MAN");
        return board;
    }

    private Map<String, Object> eventEnvelope(String type, Map<String, Object> data) {
        return Map.of("type", type, "data", data);
    }

    private DraughtsBotAdapter gameStarted() {
        DraughtsBotAdapter adapter = new DraughtsBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("GAME_STARTED", Map.of(
                "playerA", PLAYER_A, "playerB", PLAYER_B, "board", startingBoard(), "turnSeconds", 60)), PLAYER_B, Difficulty.MEDIUM);
        return adapter;
    }

    @Test
    void doesNothingWhenItIsNotTheBotsGame() {
        DraughtsBotAdapter adapter = gameStarted();
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame("PHASE", Map.of("phase", "TurnA", "round", 1), "someone-else", Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void doesNothingWhenItIsNotTheBotsTurn() {
        DraughtsBotAdapter adapter = gameStarted(); // GAME_STARTED itself already leaves phase at TurnA
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame("PHASE", Map.of("phase", "TurnA", "round", 1), PLAYER_B, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void doesNotPromptOffABarePhaseFrame() {
        // PHASE frames arrive before the domain EVENTs that describe what just
        // happened (see GameOrchestrator.afterMutation) — acting here would mean
        // deciding on a stale board. The adapter must wait for the EVENT.
        DraughtsBotAdapter adapter = gameStarted();
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame("PHASE", Map.of("phase", "TurnB", "round", 2), PLAYER_B, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void promptsWhenItBecomesTheBotsTurn() {
        DraughtsBotAdapter adapter = gameStarted();
        adapter.onFrame("PHASE", Map.of("phase", "TurnB", "round", 2), PLAYER_B, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("TURN_STARTED", Map.of("side", "B", "mustCapture", false)), PLAYER_B, Difficulty.MEDIUM);
        assertThat(prompt).isPresent();
        assertThat(prompt.get().systemPrompt()).contains("side B");
        assertThat(prompt.get().userPrompt()).contains("Legal moves:");
    }

    @Test
    void doesNothingOnceTheGameIsOver() {
        DraughtsBotAdapter adapter = gameStarted();
        adapter.onFrame("EVENT", eventEnvelope("GAME_OVER", Map.of("winningSide", "A")), PLAYER_B, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame("PHASE", Map.of("phase", "TurnB", "round", 4), PLAYER_B, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void tracksBoardMutationsFromEvents() {
        DraughtsBotAdapter adapter = gameStarted();
        // A man from square 15 moves to 20 (a real legal opening move).
        adapter.onFrame("EVENT", eventEnvelope("PIECE_MOVED", Map.of("from", 15, "to", 20, "side", "A")), PLAYER_B, Difficulty.MEDIUM);
        adapter.onFrame("PHASE", Map.of("phase", "TurnB", "round", 2), PLAYER_B, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("TURN_STARTED", Map.of("side", "B", "mustCapture", false)), PLAYER_B, Difficulty.MEDIUM);
        assertThat(prompt).isPresent();
        // square 15 should no longer show up as an A piece in the rendered board text
        assertThat(prompt.get().userPrompt()).contains("20:A_MAN");
    }

    @Test
    void parsesAWellFormedMoveResponse() {
        DraughtsBotAdapter adapter = gameStarted();
        Optional<PlayerAction> action = adapter.parseAction("{\"from\": 32, \"to\": 28}", PLAYER_B);
        assertThat(action).isPresent();
        assertThat(action.get().type()).isEqualTo("MOVE");
        assertThat(action.get().actor()).isEqualTo(PLAYER_B);
        assertThat(action.get().data()).containsEntry("from", 32).containsEntry("to", 28);
    }

    @Test
    void parsesAMoveResponseEvenWithSurroundingChatter() {
        DraughtsBotAdapter adapter = gameStarted();
        Optional<PlayerAction> action = adapter.parseAction(
                "Sure, I'll play this: {\"from\": 32, \"to\": 28} — good luck!", PLAYER_B);
        assertThat(action).isPresent();
        assertThat(action.get().data()).containsEntry("from", 32).containsEntry("to", 28);
    }

    @Test
    void rejectsGarbageResponses() {
        DraughtsBotAdapter adapter = gameStarted();
        assertThat(adapter.parseAction("", PLAYER_B)).isEmpty();
        assertThat(adapter.parseAction("I don't know what to play", PLAYER_B)).isEmpty();
        assertThat(adapter.parseAction(null, PLAYER_B)).isEmpty();
    }

    @Test
    void fallbackActionIsAlwaysALegalMove() {
        DraughtsBotAdapter adapter = gameStarted();
        adapter.onFrame("PHASE", Map.of("phase", "TurnB", "round", 2), PLAYER_B, Difficulty.MEDIUM);
        Optional<PlayerAction> action = adapter.fallbackAction(PLAYER_B);
        assertThat(action).isPresent();
        assertThat(action.get().type()).isEqualTo("MOVE");
        int from = (int) action.get().data().get("from");
        // must be one of B's starting men (squares 30-49)
        assertThat(from).isBetween(30, 49);
    }

    @Test
    void fallbackActionIsEmptyForAnUnknownPlayer() {
        DraughtsBotAdapter adapter = gameStarted();
        assertThat(adapter.fallbackAction("nobody")).isEmpty();
    }
}
