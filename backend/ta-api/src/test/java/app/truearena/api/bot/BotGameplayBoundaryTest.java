package app.truearena.api.bot;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;
import reactor.core.publisher.Flux;
import reactor.test.StepVerifier;
import org.reactivestreams.Publisher;
import org.springframework.core.io.buffer.DefaultDataBufferFactory;
import org.springframework.web.reactive.socket.WebSocketMessage;
import org.springframework.web.reactive.socket.WebSocketSession;

import java.net.URI;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

class BotGameplayBoundaryTest {
    private final ObjectMapper json = new ObjectMapper();

    private void frame(BotRuntime runtime, Sinks.Many<String> outbound, String type, Map<String, Object> payload) throws Exception {
        runtime.onFrame(json.writeValueAsString(Map.of("type", type, "payload", payload)), outbound)
                .block(Duration.ofSeconds(2));
    }

    private BotRuntime runtime(GameBotAdapter adapter, LlmMovePicker picker) {
        return new BotRuntime(json, URI.create("ws://localhost/unused"), adapter, picker,
                "bot", Difficulty.HARD, "Cyber", adapter.gameType());
    }

    @Test void noRegisteredGameDelegatesGameplayToAModel() {
        var factory = new GameBotAdapterFactory();
        for (String game : List.of("chess", "draughts", "goosi", "whot", "ludo", "monopoly", "truearena", "wordbluff"))
            assertThat(factory.create(game).decidesLocally()).as(game).isTrue();
    }

    @Test void hungCommunicationCannotDelayAVoteAndItsLateReplyIsDiscarded() throws Exception {
        Sinks.One<String> reply = Sinks.one();
        AtomicInteger speechRequests = new AtomicInteger();
        var bot = new TrueArenaBotAdapter();
        BotRuntime runtime = runtime(bot, (system, user, level) -> {
            speechRequests.incrementAndGet();
            assertThat(system).doesNotContain("yourRole", "fellowTraitors", "CAST_VOTE", "NIGHT_TARGET");
            return reply.asMono();
        });
        Sinks.Many<String> outbound = Sinks.many().unicast().onBackpressureBuffer();
        List<String> sent = new CopyOnWriteArrayList<>();
        outbound.asFlux().subscribe(sent::add);
        try {
            frame(runtime, outbound, "SNAPSHOT", Map.of("phase", "RoundTable", "yourRole", "traitor",
                    "fellowTraitors", List.of("ally"), "alive", List.of("bot", "human", "ally")));
            frame(runtime, outbound, "EVENT", Map.of("type", "ROUND_TABLE_OPEN", "data", Map.of()));
            assertThat(speechRequests).hasValue(1);
            frame(runtime, outbound, "PHASE", Map.of("phase", "Vote"));
            frame(runtime, outbound, "EVENT", Map.of("type", "VOTE_OPEN", "data", Map.of()));
            assertThat(sent).anySatisfy(message -> assertThat(message).contains("CAST_VOTE", "human"));
            assertThat(sent).noneSatisfy(message -> assertThat(message).contains("CHAT_SEND"));
            reply.tryEmitValue("This reply belongs to the previous discussion.");
            assertThat(sent).noneSatisfy(message -> assertThat(message).contains("previous discussion"));
        } finally { runtime.stop(); }
    }

    @Test void wordBluffCluesNeedNoLanguageModel() throws Exception {
        AtomicInteger requests = new AtomicInteger();
        BotRuntime runtime = runtime(new WordBluffBotAdapter(), (system, user, level) -> {
            requests.incrementAndGet();
            return Mono.never();
        });
        Sinks.Many<String> outbound = Sinks.many().unicast().onBackpressureBuffer();
        List<String> sent = new CopyOnWriteArrayList<>();
        outbound.asFlux().subscribe(sent::add);
        try {
            frame(runtime, outbound, "SNAPSHOT", Map.of("phase", "Turn", "textMode", true, "describer", "bot",
                    "yourWord", "elephant", "wordIndex", 2, "clockStarted", true,
                    "hasActiveCategory", true, "hasActiveWord", true));
            assertThat(sent).anySatisfy(message -> assertThat(message).contains("TEXT_CLUE"));
            assertThat(requests).hasValue(0);
        } finally { runtime.stop(); }
    }

    @Test void theTellConfirmsAndBuzzesOffTurnWithoutWaitingForLanguageGeneration() throws Exception {
        BotRuntime runtime = runtime(new WhotBotAdapter(), (system, user, level) -> Mono.never());
        Sinks.Many<String> outbound = Sinks.many().unicast().onBackpressureBuffer();
        List<String> sent = new CopyOnWriteArrayList<>(); outbound.asFlux().subscribe(sent::add);
        var view = new java.util.HashMap<String, Object>();
        view.put("mode", "tell"); view.put("phase", "Signals"); view.put("turnPlayer", "partner");
        view.put("players", List.of("partner", "bot", "a", "b"));
        view.put("teams", List.of(List.of("partner", "bot"), List.of("a", "b")));
        view.put("yourSignal", "🪐"); view.put("yourSignalConfirmed", false);
        view.put("yourHand", List.of("circle-3", "triangle-7", "cross-2"));
        view.put("handSizes", Map.of("partner", 3));
        try {
            frame(runtime, outbound, "SNAPSHOT", view);
            assertThat(sent).anySatisfy(message -> assertThat(message).contains("CHOOSE_SIGNAL"));
            view.put("phase", "Waiting"); view.put("yourSignalConfirmed", true);
            view.put("signal", Map.of("id", 9, "by", "partner", "symbol", "🪐", "sentAtMs", System.currentTimeMillis()));
            frame(runtime, outbound, "SNAPSHOT", view);
            assertThat(sent).anySatisfy(message -> assertThat(message).contains("BUZZ", "signalId"));
        } finally { runtime.stop(); }
    }

    @Test void failedModelDoesNotPreventLudoRolling() throws Exception {
        BotRuntime runtime = runtime(new LudoBotAdapter(), (system, user, level) -> Mono.error(new IllegalStateException("offline")));
        Sinks.Many<String> outbound = Sinks.many().unicast().onBackpressureBuffer();
        List<String> sent = new CopyOnWriteArrayList<>();
        outbound.asFlux().subscribe(sent::add);
        try {
            frame(runtime, outbound, "SNAPSHOT", Map.of("phase", "Turn", "turnPlayer", "bot", "dice", List.of()));
            assertThat(sent).anySatisfy(message -> assertThat(message).contains("PLAYER_ACTION", "ROLL"));
        } finally { runtime.stop(); }
    }

    @Test void rejectedGameplayIsRetriedOnceAndStoppingCancelsPendingCommunication() throws Exception {
        AtomicInteger cancelled = new AtomicInteger();
        BotRuntime runtime = runtime(new TrueArenaBotAdapter(), (system, user, level) ->
                Mono.<String>never().doOnCancel(cancelled::incrementAndGet));
        Sinks.Many<String> outbound = Sinks.many().unicast().onBackpressureBuffer();
        List<String> sent = new CopyOnWriteArrayList<>();
        outbound.asFlux().subscribe(sent::add);
        try {
            frame(runtime, outbound, "SNAPSHOT", Map.of("phase", "RoundTable", "yourRole", "faithful",
                    "alive", List.of("bot", "human")));
            frame(runtime, outbound, "EVENT", Map.of("type", "ROUND_TABLE_OPEN", "data", Map.of()));
            frame(runtime, outbound, "PHASE", Map.of("phase", "Vote"));
            frame(runtime, outbound, "EVENT", Map.of("type", "VOTE_OPEN", "data", Map.of()));
            frame(runtime, outbound, "ERROR", Map.of("code", "RETRY_TEST"));
            frame(runtime, outbound, "ERROR", Map.of("code", "RETRY_TEST"));
            assertThat(sent.stream().filter(message -> message.contains("CAST_VOTE"))).hasSize(2);
        } finally { runtime.stop(); }
        assertThat(cancelled).hasValue(1);
    }

    @Test void remoteSocketClosureCompletesTheHandlerAndCancelsDialogue() throws Exception {
        AtomicInteger cancelled = new AtomicInteger();
        BotRuntime runtime = runtime(new TrueArenaBotAdapter(), (system, user, level) ->
                Mono.<String>never().doOnCancel(cancelled::incrementAndGet));
        Sinks.Many<String> outbound = Sinks.many().unicast().onBackpressureBuffer();
        try {
            frame(runtime, outbound, "SNAPSHOT", Map.of("phase", "RoundTable", "yourRole", "faithful",
                    "alive", List.of("bot", "human")));
            frame(runtime, outbound, "EVENT", Map.of("type", "ROUND_TABLE_OPEN", "data", Map.of()));
            WebSocketSession session = mock(WebSocketSession.class);
            when(session.receive()).thenReturn(Flux.empty());
            when(session.textMessage(anyString())).thenAnswer(call -> new WebSocketMessage(WebSocketMessage.Type.TEXT,
                    DefaultDataBufferFactory.sharedInstance.wrap(((String) call.getArgument(0)).getBytes(java.nio.charset.StandardCharsets.UTF_8))));
            when(session.send(any())).thenAnswer(call -> Flux.from((Publisher<?>) call.getArgument(0)).then());
            StepVerifier.create(runtime.handle(session)).expectComplete().verify(Duration.ofSeconds(2));
            assertThat(cancelled).hasValue(1);
        } finally { runtime.stop(); }
    }
}
