package app.truearena.api.ws;

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
import reactor.core.publisher.Sinks;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

/**
 * A player who leaves the game screen (app to the background) tells the room
 * with PRESENCE, so the others can show them amber, then grey — while the
 * game itself carries on untouched.
 */
class GameOrchestratorPresenceTest {

    private final ObjectMapper mapper = new ObjectMapper()
            .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
    private final GameOrchestrator server = new GameOrchestrator(null, null, mock(RoomEventLog.class), null, null,
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

    private void presence(RoomRuntime rt, String userId, boolean away) throws Exception {
        String frame = mapper.writeValueAsString(Envelope.of(MessageType.PRESENCE, Map.of("away", away)));
        server.handleFrame(rt, userId, frame, false).block();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> snapshotFor(RoomRuntime rt, String userId) throws Exception {
        var sink = Sinks.many().unicast().onBackpressureBuffer();
        rt.unicast.put(userId, sink);
        List<Envelope> frames = new ArrayList<>();
        var sub = sink.asFlux().cast(Envelope.class).subscribe(frames::add);
        try {
            server.handleFrame(rt, userId,
                    mapper.writeValueAsString(Envelope.of(MessageType.HELLO, Map.of("lastSeq", 0))), false).block();
        } finally {
            sub.dispose();
        }
        return (Map<String, Object>) frames.stream().filter(f -> f.type() == MessageType.SNAPSHOT)
                .findFirst().orElseThrow().payload();
    }

    @Test
    void steppingAwayIsSharedAndComingBackClearsIt() throws Exception {
        RoomRuntime rt = startedRoom();

        presence(rt, "b", true);
        long leftAt = rt.awaySinceMs.get("b");
        assertThat(rt.connectedUserIds).contains("b"); // still connected — only the light changes
        assertThat((Map<String, Object>) snapshotFor(rt, "a").get("awaySince")).containsKey("b");

        // Saying "away" again doesn't restart the five minutes.
        presence(rt, "b", true);
        assertThat(rt.awaySinceMs.get("b")).isEqualTo(leftAt);

        presence(rt, "b", false);
        assertThat(rt.awaySinceMs).doesNotContainKey("b");
    }
}
