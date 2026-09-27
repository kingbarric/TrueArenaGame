package app.truearena.api.ws;

import app.truearena.engine.GameEvent;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.game.whot.WhotConfig;
import app.truearena.game.whot.WhotModule;
import app.truearena.room.RoomRuntime;
import app.truearena.ws.contract.Envelope;
import app.truearena.ws.contract.MessageType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Sinks;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import static org.assertj.core.api.Assertions.assertThat;

class WhotSpectatorTest {
    private final ObjectMapper mapper = new ObjectMapper();
    private final GameOrchestrator server = new GameOrchestrator(null, null, null, null, null,
            null, null, null, null, null, null, null, mapper, null);
    private final WhotModule module = new WhotModule();

    private RoomRuntime table() {
        var rt = new RoomRuntime(UUID.randomUUID(), "a");
        rt.config = WhotConfig.defaults();
        var state = module.initialState(List.of("a", "b"), rt.config, RandomSource.seeded(7));
        state = module.onPlayerAction(state, PlayerAction.of("a", "DEAL", Map.of("rounds", 5)));
        state = module.onPlayerAction(state, PlayerAction.of("a", "START", Map.of()));
        rt.start(module, state, UUID.randomUUID());
        return rt;
    }

    @Test
    void lateSpectatorReceivesTheCurrentTableWithoutAnyHand() {
        var rt = table();
        var sink = Sinks.many().unicast().onBackpressureBuffer();
        rt.unicast.put("viewer", sink);
        var frames = new ArrayList<Envelope>();
        var subscription = sink.asFlux().cast(Envelope.class).subscribe(frames::add);
        try {
            server.onSpectatorConnect(rt, "viewer").block();
            var snapshot = frames.getFirst().payload();
            assertThat(snapshot.get("phase")).isEqualTo("Turn");
            assertThat(snapshot.get("topCard")).isEqualTo(module.broadcastState(rt.state()).data().get("topCard"));
            assertThat(snapshot).containsKeys("players", "handSizes", "marketLeft", "secondsLeft");
            assertThat(snapshot).doesNotContainKeys("yourHand", "hands", "yourTurn");
        } finally { subscription.dispose(); }
    }

    @Test
    void spectatorConnectionCannotMutateEvenWithTheDealersIdentity() throws Exception {
        var rt = table();
        // The connection mode remains read-only even without an entry in the
        // shared viewer set (e.g. another connection from this account closed).
        var sink = Sinks.many().unicast().onBackpressureBuffer();
        rt.unicast.put("a", sink);
        var frames = new ArrayList<Envelope>();
        var subscription = sink.asFlux().cast(Envelope.class).subscribe(frames::add);
        var before = rt.state();
        try {
            for (var type : List.of(MessageType.PLAYER_ACTION, MessageType.GAME_START,
                    MessageType.READY_SET, MessageType.PAUSE_TOGGLE, MessageType.MUTE_SPECTATORS_TOGGLE)) {
                server.handleFrame(rt, "a", mapper.writeValueAsString(Envelope.of(type,
                        Map.of("action", "DRAW"))), true).block();
                assertThat(frames.getLast().payload().get("code")).isEqualTo("SPECTATOR_READ_ONLY");
            }
            assertThat(rt.state()).isSameAs(before);
            assertThat(rt.paused).isFalse();
        } finally { subscription.dispose(); }
    }

    @Test
    void spectatorConnectionNeverReceivesPrivateEventsOrAnIdentityMatchedHand() {
        var rt = table();
        var secret = GameEvent.toPlayer(1, "YOUR_HAND", Map.of("cards", List.of("circle-3")), "a");
        assertThat(server.toEnvelope(rt, secret, "a", true).block()).isNull();
        assertThat(server.toEnvelope(rt, secret, "a", false).block()).isNotNull();
        var privateSnapshot = Envelope.of(MessageType.SNAPSHOT, module.visibleStateFor(rt.state(), "a").data());
        var publicSnapshot = server.toEnvelope(rt, privateSnapshot, "a", true).block();
        assertThat(publicSnapshot.payload()).doesNotContainKeys("yourHand", "yourTurn");
        assertThat(server.toEnvelope(rt, GameEvent.pub(2, "CARD_PLAYED", Map.of("card", "circle-3")), "a", true).block()).isNotNull();
    }
}
