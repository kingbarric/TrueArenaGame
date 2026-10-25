package app.truearena.api.ws;

import app.truearena.engine.GameConfig;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.game.truearena.Presets;
import app.truearena.game.truearena.TrueArenaModule;
import app.truearena.game.whot.WhotConfig;
import app.truearena.game.whot.WhotModule;
import app.truearena.room.LobbyBroadcast;
import app.truearena.room.RoomLock;
import app.truearena.room.RoomRuntime;
import app.truearena.ws.contract.Envelope;
import app.truearena.ws.contract.MessageType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * The Traitors host's clock controls: only the host pauses, a pause gives up
 * by itself after the limit, and "+2 min" adds to the running (or paused) clock.
 */
class TraitorsHostClockTest {

    private final ObjectMapper mapper = new ObjectMapper();
    private final RoomLock lock = mock(RoomLock.class);
    private final GameOrchestrator server;

    @SuppressWarnings("unchecked")
    TraitorsHostClockTest() {
        when(lock.withLock(any(), any(), any())).thenAnswer(call -> ((Supplier<Mono<?>>) call.getArgument(2)).get());
        server = new GameOrchestrator(null, lock, null, null, null,
                null, null, null, null, null, null, null, mapper, null);
    }

    private final List<String> players = List.of("host", "p2", "p3", "p4", "p5", "p6");

    /** A Traitors table sitting on the round table with a 60s clock running. */
    private RoomRuntime traitorsTable() {
        GameConfig config = Presets.CLASSIC_CONSPIRACY.config();
        var module = new TrueArenaModule();
        var rt = new RoomRuntime(UUID.randomUUID(), "host");
        rt.config = config;
        rt.start(module, module.initialState(players, config, RandomSource.seeded(5)), UUID.randomUUID());
        rt.connectedUserIds.addAll(players);
        armClock(rt, 60_000);
        return rt;
    }

    private void armClock(RoomRuntime rt, long ms) {
        rt.timerForPhase = rt.state().phase();
        rt.timerForRound = rt.state().round();
        rt.timerDeadlineMs = System.currentTimeMillis() + ms;
        rt.timer = Mono.never().subscribe();
    }

    private List<Object> errorsFor(RoomRuntime rt, String userId) {
        Sinks.Many<Object> sink = Sinks.many().unicast().onBackpressureBuffer();
        rt.unicast.put(userId, sink);
        List<Object> got = new CopyOnWriteArrayList<>();
        sink.asFlux().subscribe(got::add);
        return got;
    }

    private List<LobbyBroadcast> broadcasts(RoomRuntime rt) {
        List<LobbyBroadcast> got = new CopyOnWriteArrayList<>();
        rt.bus.asFlux().filter(LobbyBroadcast.class::isInstance).cast(LobbyBroadcast.class).subscribe(got::add);
        return got;
    }

    private void send(RoomRuntime rt, String userId, MessageType type, Map<String, Object> payload) throws Exception {
        server.handleFrame(rt, userId, mapper.writeValueAsString(Envelope.of(type, payload)), false).block();
    }

    private static String code(Object frame) {
        return String.valueOf(((Envelope) frame).payload().get("code"));
    }

    @Test
    void onlyTheHostCanPauseATraitorsTable() throws Exception {
        RoomRuntime rt = traitorsTable();
        List<Object> errors = errorsFor(rt, "p2");

        send(rt, "p2", MessageType.PAUSE_TOGGLE, Map.of());

        assertThat(rt.paused).isFalse();
        assertThat(errors).extracting(TraitorsHostClockTest::code).containsExactly("NOT_HOST");

        send(rt, "host", MessageType.PAUSE_TOGGLE, Map.of());
        assertThat(rt.paused).isTrue();
        assertThat(rt.pauseLimitDeadlineMs).isPositive();

        send(rt, "host", MessageType.PAUSE_TOGGLE, Map.of());
        assertThat(rt.paused).isFalse();
        assertThat(rt.pauseLimit).isNull();
        assertThat(rt.pauseLimitDeadlineMs).isZero();
        rt.cancelTimer();
    }

    @Test
    void aPauseTellsTheTableWhenItWillResumeByItself() throws Exception {
        RoomRuntime rt = traitorsTable();
        List<LobbyBroadcast> seen = broadcasts(rt);

        send(rt, "host", MessageType.PAUSE_TOGGLE, Map.of());

        LobbyBroadcast paused = seen.stream().filter(b -> b.type().equals("GAME_PAUSED")).findFirst().orElseThrow();
        assertThat((Integer) paused.data().get("resumesInSeconds")).isBetween(599, 600);
        rt.cancelPauseLimit();
    }

    @Test
    void aForgottenPauseResumesItselfAtTheLimit() throws Exception {
        RoomRuntime rt = traitorsTable();
        server.hostPauseLimit = Duration.ofMillis(80);
        List<LobbyBroadcast> seen = broadcasts(rt);

        send(rt, "host", MessageType.PAUSE_TOGGLE, Map.of());
        assertThat(rt.paused).isTrue();

        long giveUp = System.currentTimeMillis() + 3_000;
        while (rt.paused && System.currentTimeMillis() < giveUp) Thread.sleep(20);
        assertThat(rt.paused).isFalse();
        assertThat(rt.timerDeadlineMs - System.currentTimeMillis()).isGreaterThan(55_000);
        assertThat(seen).anySatisfy(b -> {
            assertThat(b.type()).isEqualTo("GAME_RESUMED");
            assertThat(b.data().get("reason")).isEqualTo("pause_limit");
        });
        rt.cancelTimer();
    }

    @Test
    void theHostAddsTwoMinutesToTheRunningClock() throws Exception {
        RoomRuntime rt = traitorsTable();
        List<LobbyBroadcast> seen = broadcasts(rt);

        send(rt, "host", MessageType.HOST_CONTROL, Map.of("cmd", "EXTEND_TIMER"));

        long left = rt.timerDeadlineMs - System.currentTimeMillis();
        assertThat(left).isBetween(175_000L, 180_000L);
        assertThat(rt.timerForPhase).isEqualTo(rt.state().phase());
        assertThat(seen).anySatisfy(b -> {
            assertThat(b.type()).isEqualTo("TIMER_EXTENDED");
            assertThat(b.data().get("addedSeconds")).isEqualTo(GameOrchestrator.EXTEND_SECONDS);
        });
        rt.cancelTimer();
    }

    @Test
    void timeAddedWhilePausedIsBankedForTheResume() throws Exception {
        RoomRuntime rt = traitorsTable();
        send(rt, "host", MessageType.PAUSE_TOGGLE, Map.of());
        long banked = rt.timerRemainingMs;

        send(rt, "host", MessageType.HOST_CONTROL, Map.of("cmd", "EXTEND_TIMER"));

        assertThat(rt.timerRemainingMs).isEqualTo(banked + 120_000);
        rt.cancelPauseLimit();
    }

    @Test
    void playersCantAddTime() throws Exception {
        RoomRuntime rt = traitorsTable();
        long before = rt.timerDeadlineMs;
        List<Object> errors = errorsFor(rt, "p3");

        send(rt, "p3", MessageType.HOST_CONTROL, Map.of("cmd", "EXTEND_TIMER"));

        assertThat(rt.timerDeadlineMs).isEqualTo(before);
        assertThat(errors).extracting(TraitorsHostClockTest::code).containsExactly("NOT_HOST");
        rt.cancelTimer();
    }

    @Test
    void otherGamesKeepTheirEitherPlayerPauseAndHaveNoExtend() throws Exception {
        var rt = new RoomRuntime(UUID.randomUUID(), "a");
        rt.config = WhotConfig.defaults();
        var module = new WhotModule();
        var state = module.initialState(List.of("a", "b"), rt.config, RandomSource.seeded(8));
        state = module.onPlayerAction(state, PlayerAction.of("a", "DEAL", Map.of("rounds", 5)));
        state = module.onPlayerAction(state, PlayerAction.of("a", "START", Map.of()));
        rt.start(module, state, UUID.randomUUID());
        rt.connectedUserIds.addAll(List.of("a", "b"));
        armClock(rt, 30_000);
        List<Object> errors = errorsFor(rt, "a");

        send(rt, "b", MessageType.PAUSE_TOGGLE, Map.of());
        assertThat(rt.paused).isTrue();
        assertThat(rt.pauseLimitDeadlineMs).isZero();

        send(rt, "a", MessageType.HOST_CONTROL, Map.of("cmd", "EXTEND_TIMER"));
        assertThat(errors).extracting(TraitorsHostClockTest::code).containsExactly("UNSUPPORTED");
        rt.cancelTimer();
    }
}
