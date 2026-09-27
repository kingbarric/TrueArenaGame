package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link TrueArenaBotAdapter} driven with the exact frame shapes
 * {@code GameOrchestrator}/{@code TrueArenaModule} actually send.
 */
class TrueArenaBotAdapterTest {

    private static final String BOT = "bot-1";
    private static final String ALICE = "alice";
    private static final String BOB = "bob";
    private static final String CAROL = "carol";

    private Map<String, Object> eventEnvelope(String type, Map<String, Object> data) {
        return Map.of("type", type, "data", data);
    }

    private TrueArenaBotAdapter traitorBot() {
        TrueArenaBotAdapter adapter = new TrueArenaBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("GAME_STARTED",
                Map.of("players", List.of(ALICE, BOB, CAROL, BOT), "traitors", 1, "preset", "classic")), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("ROLE_ASSIGNED", Map.of("role", "traitor")), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("FELLOW_TRAITORS", Map.of("ids", List.of())), BOT, Difficulty.MEDIUM);
        return adapter;
    }

    private TrueArenaBotAdapter faithfulBot() {
        TrueArenaBotAdapter adapter = new TrueArenaBotAdapter();
        adapter.onFrame("EVENT", eventEnvelope("GAME_STARTED",
                Map.of("players", List.of(ALICE, BOB, CAROL, BOT), "traitors", 1, "preset", "classic")), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("ROLE_ASSIGNED", Map.of("role", "faithful")), BOT, Difficulty.MEDIUM);
        return adapter;
    }

    @Test
    void doesNothingWhileRoleIsUnknown() {
        TrueArenaBotAdapter adapter = new TrueArenaBotAdapter();
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "PHASE", Map.of("phase", "Night", "round", 1), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void doesNotPromptOffABarePhaseFrame() {
        TrueArenaBotAdapter adapter = traitorBot();
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "PHASE", Map.of("phase", "Night", "round", 1), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void traitorPromptsForANightTargetExcludingFellowTraitors() {
        TrueArenaBotAdapter adapter = traitorBot();
        adapter.onFrame("PHASE", Map.of("phase", "Night", "round", 1), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("NIGHT_FALLS", Map.of("round", 1)), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isPresent();
        assertThat(prompt.get().userPrompt()).contains(ALICE).contains(BOB).contains(CAROL).doesNotContain(BOT);
    }

    @Test
    void faithfulPlayerNeverPromptsAtNight() {
        TrueArenaBotAdapter adapter = faithfulBot();
        adapter.onFrame("PHASE", Map.of("phase", "Night", "round", 1), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("NIGHT_FALLS", Map.of("round", 1)), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void doesNotReDecideTwiceInTheSamePhase() {
        TrueArenaBotAdapter adapter = traitorBot();
        adapter.onFrame("PHASE", Map.of("phase", "Night", "round", 1), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("NIGHT_FALLS", Map.of("round", 1)), BOT, Difficulty.MEDIUM);
        // a fellow traitor's submission is broadcast to this bot too (emitToRole) —
        // it must not trigger a second prompt for the same Night.
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("NIGHT_TARGET_SET", Map.of("by", ALICE, "target", BOB)), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void anyLivingPlayerPromptsToVoteExcludingSelf() {
        TrueArenaBotAdapter adapter = faithfulBot();
        adapter.onFrame("PHASE", Map.of("phase", "Vote", "round", 1), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("MICS_FORCE_MUTED", Map.of()), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isPresent();
        assertThat(prompt.get().userPrompt()).contains(ALICE).contains(BOB).contains(CAROL).doesNotContain(BOT);
    }

    @Test
    void eliminatedPlayerNeverPromptsToVote() {
        TrueArenaBotAdapter adapter = faithfulBot();
        adapter.onFrame("EVENT", eventEnvelope("PLAYER_ELIMINATED",
                Map.of("id", BOT, "cause", "murder", "roleShown", false)), BOT, Difficulty.MEDIUM);
        adapter.onFrame("PHASE", Map.of("phase", "Vote", "round", 1), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("MICS_FORCE_MUTED", Map.of()), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void doesNothingOnceTheGameIsOver() {
        TrueArenaBotAdapter adapter = faithfulBot();
        adapter.onFrame("EVENT", eventEnvelope("GAME_OVER", Map.of("winningSide", "faithful", "rounds", 3)), BOT, Difficulty.MEDIUM);
        adapter.onFrame("PHASE", Map.of("phase", "Vote", "round", 4), BOT, Difficulty.MEDIUM);
        Optional<GameBotAdapter.BotPrompt> prompt = adapter.onFrame(
                "EVENT", eventEnvelope("MICS_FORCE_MUTED", Map.of()), BOT, Difficulty.MEDIUM);
        assertThat(prompt).isEmpty();
    }

    @Test
    void parsesAWellFormedNightTargetResponse() {
        TrueArenaBotAdapter adapter = traitorBot();
        adapter.onFrame("PHASE", Map.of("phase", "Night", "round", 1), BOT, Difficulty.MEDIUM);
        Optional<PlayerAction> action = adapter.parseAction("{\"target\": \"" + ALICE + "\"}", BOT);
        assertThat(action).isPresent();
        assertThat(action.get().type()).isEqualTo("NIGHT_TARGET");
        assertThat(action.get().data()).containsEntry("target", ALICE);
    }

    @Test
    void parsesAWellFormedVoteResponse() {
        TrueArenaBotAdapter adapter = faithfulBot();
        adapter.onFrame("PHASE", Map.of("phase", "Vote", "round", 1), BOT, Difficulty.MEDIUM);
        Optional<PlayerAction> action = adapter.parseAction("{\"target\": \"" + BOB + "\"}", BOT);
        assertThat(action).isPresent();
        assertThat(action.get().type()).isEqualTo("CAST_VOTE");
    }

    @Test
    void rejectsATargetThatIsNotAliveOrIsSelf() {
        TrueArenaBotAdapter adapter = faithfulBot();
        adapter.onFrame("PHASE", Map.of("phase", "Vote", "round", 1), BOT, Difficulty.MEDIUM);
        assertThat(adapter.parseAction("{\"target\": \"ghost\"}", BOT)).isEmpty();
        assertThat(adapter.parseAction("{\"target\": \"" + BOT + "\"}", BOT)).isEmpty();
    }

    @Test
    void garbageOrEmptyResponsesFailToParse() {
        TrueArenaBotAdapter adapter = faithfulBot();
        assertThat(adapter.parseAction("not json at all", BOT)).isEmpty();
        assertThat(adapter.parseAction("", BOT)).isEmpty();
        assertThat(adapter.parseAction(null, BOT)).isEmpty();
    }

    @Test
    void fallbackNightTargetIsAlwaysLegal() {
        TrueArenaBotAdapter adapter = traitorBot();
        adapter.onFrame("PHASE", Map.of("phase", "Night", "round", 1), BOT, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("NIGHT_FALLS", Map.of("round", 1)), BOT, Difficulty.MEDIUM);
        Optional<PlayerAction> action = adapter.fallbackAction(BOT);
        assertThat(action).isPresent();
        assertThat(action.get().type()).isEqualTo("NIGHT_TARGET");
        assertThat(List.of(ALICE, BOB, CAROL)).contains((String) action.get().data().get("target"));
    }

    @Test
    void fallbackVoteIsAlwaysLegal() {
        TrueArenaBotAdapter adapter = faithfulBot();
        adapter.onFrame("PHASE", Map.of("phase", "Vote", "round", 1), BOT, Difficulty.MEDIUM);
        Optional<PlayerAction> action = adapter.fallbackAction(BOT);
        assertThat(action).isPresent();
        assertThat(action.get().type()).isEqualTo("CAST_VOTE");
        assertThat(List.of(ALICE, BOB, CAROL)).contains((String) action.get().data().get("target"));
    }

    @Test
    void fallbackIsEmptyOutsideNightOrVote() {
        TrueArenaBotAdapter adapter = faithfulBot();
        assertThat(adapter.fallbackAction(BOT)).isEmpty();
    }
}
