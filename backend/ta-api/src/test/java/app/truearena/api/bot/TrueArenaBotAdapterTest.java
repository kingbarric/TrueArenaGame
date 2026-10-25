package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

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

    /** Never volunteers beyond its turn, so who speaks is fixed for a test. */
    private static java.util.Random steady() {
        return new java.util.Random(7) {
            @Override public int nextInt(int bound) { return bound - 1; }
            @Override public double nextDouble() { return 0.99; }
        };
    }

    private static final List<String> AGENTS = List.of("bot-1", "bot-2", "bot-3");

    /** An agent at a table of three people and three agents, at the round table, everyone named. */
    private TrueArenaBotAdapter agentAtTable(String me) {
        TrueArenaBotAdapter adapter = new TrueArenaBotAdapter(steady());
        adapter.onFrame("SNAPSHOT", Map.of("lobby", true, "members", List.of(
                Map.of("userId", ALICE, "nickname", "Alice"), Map.of("userId", BOB, "nickname", "Bob"),
                Map.of("userId", CAROL, "nickname", "Carol"), Map.of("userId", "bot-1", "nickname", "Nova"),
                Map.of("userId", "bot-2", "nickname", "Zara"), Map.of("userId", "bot-3", "nickname", "Rex"))), me, Difficulty.MEDIUM);
        adapter.onFrame("EVENT", eventEnvelope("GAME_STARTED",
                Map.of("players", List.of(ALICE, BOB, CAROL, "bot-1", "bot-2", "bot-3"))), me, Difficulty.MEDIUM);
        adapter.onFrame("SNAPSHOT", Map.of("lobby", false, "phase", "RoundTable", "round", 1, "yourRole", "faithful",
                "alive", List.of(ALICE, BOB, CAROL, "bot-1", "bot-2", "bot-3"), "botPlayerIds", AGENTS), me, Difficulty.MEDIUM);
        return adapter;
    }

    private static Map<String, Object> chat(String from, String text) {
        return Map.of("type", "CHAT_MESSAGE", "data", Map.of("from", from, "channel", "table", "text", text));
    }

    @Test
    void agentsTakeTurnsOpeningTheTableAndCallPeopleByName() {
        List<GameBotAdapter.BotPrompt> openers = new java.util.ArrayList<>();
        for (String agent : AGENTS) {
            agentAtTable(agent).onFrame("EVENT", eventEnvelope("ROUND_TABLE_OPEN", Map.of()), agent, Difficulty.MEDIUM)
                    .ifPresent(openers::add);
        }
        assertThat(openers).as("one agent opens, not all three").hasSize(1);
        GameBotAdapter.BotPrompt open = openers.getFirst();
        assertThat(open.speak()).isTrue();
        assertThat(open.channel()).isEqualTo("table");
        assertThat(open.fallback()).containsAnyOf("Alice", "Bob", "Carol", "Nova", "Rex");
        assertThat(open.userPrompt()).contains("Alice").doesNotContain(ALICE + ",");
    }

    @Test
    void anAgentCalledByNameAnswersInItsOwnVoiceAndTheOthersSoundDifferent() {
        Set<String> lines = new java.util.HashSet<>();
        for (String agent : AGENTS) {
            Optional<GameBotAdapter.BotPrompt> answer = agentAtTable(agent)
                    .onFrame("EVENT", chat(ALICE, "Nova, Zara, Rex — which of you is lying?"), agent, Difficulty.MEDIUM);
            assertThat(answer).as("%s was named, so it answers", agent).isPresent();
            assertThat(answer.get().fallback()).contains("Alice");
            lines.add(answer.get().fallback());
        }
        assertThat(lines).as("three agents, three different answers").hasSize(3);
    }

    @Test
    void aPersonAlwaysGetsAnAnswerButNotFromEveryAgent() {
        for (String text : List.of("I think it's Carol.", "Who voted for Bob last time?", "Something feels off.")) {
            int answered = 0;
            for (String agent : AGENTS) {
                if (agentAtTable(agent).onFrame("EVENT", chat(BOB, text), agent, Difficulty.MEDIUM).isPresent()) {
                    answered++;
                }
            }
            assertThat(answered).as("\"%s\" gets exactly one answer when nobody volunteers", text).isEqualTo(1);
        }
    }

    @Test
    void theAnswerGoesWhereThePromptWasMadeEvenIfItArrivesLater() {
        TrueArenaBotAdapter adapter = agentAtTable("bot-2");
        GameBotAdapter.BotPrompt answer = adapter.onFrame("EVENT", chat(ALICE, "Zara, talk to me"), "bot-2", Difficulty.MEDIUM)
                .orElseThrow();
        assertThat(adapter.speechAction(answer, "Fine, Alice — it's Rex.", "bot-2")).hasValueSatisfying(a -> {
            assertThat(a.type()).isEqualTo("CHAT_SEND");
            assertThat(a.data()).containsEntry("channel", "table").containsEntry("text", "Fine, Alice — it's Rex.");
        });
        assertThat(adapter.fallbackSpeech(answer)).isEqualTo(answer.fallback());
        assertThat(adapter.speechDelay()).isBetween(java.time.Duration.ofMillis(1500), java.time.Duration.ofSeconds(6));
    }

    @Test
    void aTraitorAgentNeverPointsAtItsOwnSide() {
        for (int i = 0; i < 25; i++) {
            TrueArenaBotAdapter adapter = new TrueArenaBotAdapter(new java.util.Random(i));
            adapter.playerNames(Map.of(ALICE, "Alice", BOB, "Bob", CAROL, "Carol", BOT, "Nova"));
            adapter.onFrame("EVENT", eventEnvelope("GAME_STARTED", Map.of("players", List.of(ALICE, BOB, CAROL, BOT))), BOT, Difficulty.MEDIUM);
            adapter.onFrame("EVENT", eventEnvelope("ROLE_ASSIGNED", Map.of("role", "traitor")), BOT, Difficulty.MEDIUM);
            adapter.onFrame("EVENT", eventEnvelope("FELLOW_TRAITORS", Map.of("ids", List.of(BOB))), BOT, Difficulty.MEDIUM);
            adapter.onFrame("SNAPSHOT", Map.of("lobby", false, "phase", "RoundTable", "round", 2,
                    "alive", List.of(ALICE, BOB, CAROL, BOT), "botPlayerIds", List.of(BOT)), BOT, Difficulty.MEDIUM);
            Optional<GameBotAdapter.BotPrompt> said = adapter.onFrame("EVENT", chat(ALICE, "Nova, who do you suspect?"), BOT, Difficulty.MEDIUM);
            assertThat(said).isPresent();
            assertThat(said.get().fallback()).doesNotContain("Bob");
            assertThat(said.get().systemPrompt()).contains("secretly a Traitor");
        }
    }
}
