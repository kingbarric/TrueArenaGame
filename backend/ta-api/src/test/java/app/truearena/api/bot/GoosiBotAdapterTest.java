package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link GoosiBotAdapter} driven with the exact frame shapes
 * {@code GameOrchestrator}/{@code GoosiModule} actually send.
 */
class GoosiBotAdapterTest {

    private static final String PLAYER_A = "alice";
    private static final String BOT = "bot-1";

    private List<Object> owners(String a, String b) {
        List<Object> out = new ArrayList<>();
        for (int i = 0; i < 6; i++) out.add(a);
        for (int i = 6; i < 12; i++) out.add(b);
        return out;
    }

    private List<Object> pits(int value) {
        List<Object> out = new ArrayList<>();
        for (int i = 0; i < 12; i++) out.add(value);
        return out;
    }

    private Map<String, Object> eventEnvelope(String type, Map<String, Object> data) {
        return Map.of("type", type, "data", data);
    }

    private GoosiBotAdapter gameStarted() {
        GoosiBotAdapter adapter = new GoosiBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("GAME_STARTED", Map.of(
                "players", List.of(PLAYER_A, BOT), "owner", owners(PLAYER_A, BOT),
                "pits", pits(4), "seedsPerPit", 4, "turnSeconds", 45,
                "legalPits", List.of(0, 1, 2, 3, 4, 5))), BOT, Difficulty.MEDIUM);
        return adapter;
    }

    @Test
    void doesNothingWhenItIsNotTheBotsTurn() {
        GoosiBotAdapter adapter = gameStarted(); // GAME_STARTED leaves phase at TurnP0 (alice)
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "PHASE", Map.of("phase", "TurnP0", "round", 1), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void doesNotPromptOffABarePhaseFrame() {
        GoosiBotAdapter adapter = gameStarted();
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "PHASE", Map.of("phase", "TurnP1", "round", 2), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void promptsWhenItBecomesTheBotsTurn() {
        GoosiBotAdapter adapter = gameStarted();
        adapter.onFrame("PHASE", Map.of("phase", "TurnP1", "round", 2), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("TURN_STARTED", Map.of("player", BOT)), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isPresent();
        assertThat(prompt.get().userPrompt()).contains("legal pits");
    }

    @Test
    void doesNothingOnceTheGameIsOver() {
        GoosiBotAdapter adapter = gameStarted();
        adapter.onFrame("EVENT", eventEnvelope("GAME_OVER", Map.of("winningSide", PLAYER_A, "winners", List.of(PLAYER_A))), BOT, Difficulty.MEDIUM);
        adapter.onFrame("PHASE", Map.of("phase", "TurnP1", "round", 5), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("TURN_STARTED", Map.of("player", BOT)), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void tracksRelayAndCapturesFromTheAuthoritativeFinalBoard() {
        GoosiBotAdapter adapter = gameStarted();
        adapter.onFrame("EVENT", eventEnvelope("SOWN", Map.of(
                "by", PLAYER_A, "from", 0,
                "laps", List.of(List.of(1, 2), List.of(3, 4)),
                "captures", Map.of("0:0", 1),
                "finalPits", List.of(0, 0, 0, 1, 1, 4, 3, 4, 4, 4, 4, 4))),
                BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("CAPTURED", Map.of(
                "pits", List.of(6), "count", 4, "duringSow", true)),
                BOT, Difficulty.MEDIUM);
        adapter.onFrame("PHASE", Map.of("phase", "TurnP1", "round", 2), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("TURN_STARTED", Map.of("player", BOT)), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isPresent();
        assertThat(prompt.get().userPrompt()).contains("0:0", "6:3");
        assertThat(prompt.get().systemPrompt()).contains("exactly four");
    }

    @Test
    void parsesAWellFormedPitResponse() {
        GoosiBotAdapter adapter = gameStarted();
        adapter.onFrame("PHASE", Map.of("phase", "TurnP1", "round", 2), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("TURN_STARTED", Map.of("player", BOT)), BOT, Difficulty.MEDIUM);
        Optional<PlayerAction> action = adapter.parseAction("{\"pit\": 9}", BOT);
        assertThat(action).isPresent();
        assertThat(action.get().type()).isEqualTo("SOW");
        assertThat(action.get().data()).containsEntry("pit", 9);
    }

    @Test
    void rejectsAPitThatIsNotOwnedByTheBot() {
        GoosiBotAdapter adapter = gameStarted();
        adapter.onFrame("PHASE", Map.of("phase", "TurnP1", "round", 2), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("TURN_STARTED", Map.of("player", BOT)), BOT, Difficulty.MEDIUM);
        assertThat(adapter.parseAction("{\"pit\": 0}", BOT)).isEmpty(); // pit 0 belongs to alice
    }

    @Test
    void garbageOrEmptyResponsesFailToParse() {
        GoosiBotAdapter adapter = gameStarted();
        assertThat(adapter.parseAction("not json", BOT)).isEmpty();
        assertThat(adapter.parseAction("", BOT)).isEmpty();
        assertThat(adapter.parseAction(null, BOT)).isEmpty();
    }

    @Test
    void fallbackAlwaysPicksALegalOwnedNonEmptyPit() {
        GoosiBotAdapter adapter = gameStarted();
        Optional<PlayerAction> action = adapter.fallbackAction(BOT);
        assertThat(action).isPresent();
        int pit = (int) action.get().data().get("pit");
        assertThat(pit).isBetween(6, 11); // bot owns the second row
    }

    @Test
    void fallbackMayUseAnyOwnedNonEmptyHouse() {
        GoosiBotAdapter adapter = new GoosiBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("GAME_STARTED", Map.of(
                "players", List.of(PLAYER_A, BOT), "owner", owners(PLAYER_A, BOT),
                "pits", List.of(0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 6),
                "seedsPerPit", 4, "turnSeconds", 45)), BOT, Difficulty.MEDIUM);

        Optional<PlayerAction> action = adapter.fallbackAction(BOT);

        assertThat(action).isPresent();
        assertThat((int) action.get().data().get("pit")).isBetween(6, 11);
    }

    @Test
    void owareBotUsesMandatoryFeedingAndOwarePrompt() {
        GoosiBotAdapter adapter = new GoosiBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("GAME_STARTED", Map.of(
                "players", List.of(PLAYER_A, BOT), "owner", owners(PLAYER_A, BOT),
                "pits", List.of(0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 6),
                "mode", "oware", "seedsPerPit", 4, "turnSeconds", 45)),
                BOT, Difficulty.HARD);
        adapter.onFrame("PHASE", Map.of("phase", "TurnP1", "round", 2),
                BOT, Difficulty.HARD);

        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("TURN_STARTED", Map.of("player", BOT)),
                BOT, Difficulty.HARD);

        assertThat(prompt).isPresent();
        assertThat(prompt.get().userPrompt()).contains("[11]");
        assertThat(prompt.get().systemPrompt()).contains("two or three", "grand slam");
        assertThat(adapter.parseAction("{\"pit\": 6}", BOT)).isEmpty();
        assertThat(adapter.parseAction("{\"pit\": 11}", BOT)).isPresent();
    }

    @Test
    void fallbackStillMovesWhenOpponentRowIsEmpty() {
        GoosiBotAdapter adapter = new GoosiBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("GAME_STARTED", Map.of(
                "players", List.of(PLAYER_A, BOT), "owner", owners(PLAYER_A, BOT),
                "pits", List.of(0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0),
                "seedsPerPit", 4, "turnSeconds", 45)), BOT, Difficulty.MEDIUM);

        assertThat(adapter.fallbackAction(BOT)).isPresent();
    }

    @Test
    void fallbackIsEmptyForAnUnknownPlayer() {
        GoosiBotAdapter adapter = gameStarted();
        assertThat(adapter.fallbackAction("nobody")).isEmpty();
    }
}
