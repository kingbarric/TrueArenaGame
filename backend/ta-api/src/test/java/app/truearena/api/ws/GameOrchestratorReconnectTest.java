package app.truearena.api.ws;

import app.truearena.engine.GameEvent;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.game.whot.WhotConfig;
import app.truearena.game.whot.WhotModule;
import app.truearena.room.RoomEventLog;
import app.truearena.room.RoomRuntime;
import app.truearena.ws.contract.Envelope;
import app.truearena.ws.contract.MessageType;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Sinks;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * {@code GameOrchestrator.handleHello} — the reconnect entry point. Covers both
 * branches on a started room: {@code lastSeq > 0} (incremental replay via
 * {@link RoomEventLog#replayAfter}) and {@code lastSeq == 0} (full snapshot).
 * Same unicast-sink-as-socket pattern as {@code WhotSpectatorTest}.
 */
class GameOrchestratorReconnectTest {

    // Matches Spring Boot's autoconfigured ObjectMapper (what GameOrchestrator gets for
    // real): FAIL_ON_UNKNOWN_PROPERTIES off, so a derived getter like Visibility.isPublic()
    // round-trips instead of failing deserialization on its own serialized output.
    private final ObjectMapper mapper = new ObjectMapper()
            .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
    private final RoomEventLog eventLog = mock(RoomEventLog.class);
    private final GameOrchestrator server = new GameOrchestrator(null, null, eventLog, null, null,
            null, null, null, null, null, null, null, mapper, null);
    private final WhotModule module = new WhotModule();

    private RoomRuntime startedRoom() {
        var rt = new RoomRuntime(UUID.randomUUID(), "a");
        rt.config = WhotConfig.defaults();
        var state = module.initialState(List.of("a", "b"), rt.config, RandomSource.seeded(7));
        state = module.onPlayerAction(state, PlayerAction.of("a", "DEAL", Map.of("rounds", 5)));
        state = module.onPlayerAction(state, PlayerAction.of("a", "START", Map.of()));
        rt.start(module, state, UUID.randomUUID());
        rt.connectedUserIds.add("a");
        rt.connectedUserIds.add("b");
        return rt;
    }

    private List<Envelope> connectAndCollect(RoomRuntime rt, String userId, long lastSeq) throws Exception {
        var sink = Sinks.many().unicast().onBackpressureBuffer();
        rt.unicast.put(userId, sink);
        List<Envelope> frames = new ArrayList<>();
        var sub = sink.asFlux().cast(Envelope.class).subscribe(frames::add);
        try {
            String hello = mapper.writeValueAsString(Envelope.of(MessageType.HELLO, Map.of("lastSeq", lastSeq)));
            server.handleFrame(rt, userId, hello, false).block();
        } finally {
            sub.dispose();
        }
        return frames;
    }

    @Test
    void lastSeqZero_sendsAFullSnapshotThenThePhase() throws Exception {
        RoomRuntime rt = startedRoom();

        List<Envelope> frames = connectAndCollect(rt, "a", 0);

        assertThat(frames).extracting(Envelope::type).containsExactly(MessageType.SNAPSHOT, MessageType.PHASE);
        verifyNoInteractions(eventLog);
    }

    @Test
    void lastSeqPositive_replaysOnlyVisibleEventsAfterThatSeqThenThePhase() throws Exception {
        RoomRuntime rt = startedRoom();
        GameEvent publicEvent = GameEvent.pub(6, "CARD_PLAYED", Map.of("card", "circle-3"));
        GameEvent otherPlayersHand = GameEvent.toPlayer(7, "YOUR_HAND", Map.of("cards", List.of("circle-9")), "b");
        String j1 = mapper.writeValueAsString(publicEvent);
        String j2 = mapper.writeValueAsString(otherPlayersHand);
        when(eventLog.replayAfter(eq(rt.roomId), eq(5L))).thenReturn(Flux.just(j1, j2));

        List<Envelope> frames = connectAndCollect(rt, "a", 5);

        // The public event is replayed to "a"; "b"'s own private hand is not.
        assertThat(frames).anyMatch(f -> f.type() == MessageType.EVENT && "CARD_PLAYED".equals(f.payload().get("type")));
        assertThat(frames).noneMatch(f -> f.type() == MessageType.EVENT && "YOUR_HAND".equals(f.payload().get("type")));
        assertThat(frames).last().extracting(Envelope::type).isEqualTo(MessageType.PHASE);
    }
}
