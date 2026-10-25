package app.truearena.api.ws;

import app.truearena.engine.RandomSource;
import app.truearena.game.draughts.DraughtsConfig;
import app.truearena.game.draughts.DraughtsModule;
import app.truearena.game.truearena.Presets;
import app.truearena.game.truearena.TrueArenaModule;
import app.truearena.room.LobbyBroadcast;
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

/** Watching a Traitors table: the whole public game, none of its secrets, and reactions. */
class TraitorsSpectatorTest {
    private final ObjectMapper mapper = new ObjectMapper();
    private final GameOrchestrator server = new GameOrchestrator(null, null, null, null, null,
            null, null, null, null, null, null, null, mapper, null);

    private static final List<String> PLAYERS = List.of("p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8");

    private RoomRuntime table() {
        var rt = new RoomRuntime(UUID.randomUUID(), "p1");
        var module = new TrueArenaModule();
        var cfg = Presets.CLASSIC_CONSPIRACY.config();
        rt.config = cfg;
        rt.start(module, module.initialState(PLAYERS, cfg, RandomSource.seeded(3)), UUID.randomUUID());
        return rt;
    }

    private static List<Envelope> listen(RoomRuntime rt, String user) {
        var sink = Sinks.many().unicast().onBackpressureBuffer();
        rt.unicast.put(user, sink);
        var frames = new ArrayList<Envelope>();
        sink.asFlux().cast(Envelope.class).subscribe(frames::add);
        return frames;
    }

    @Test void aLateSpectatorSeesTheTableButNoRoleOrNightSecret() {
        var rt = table();
        var frames = listen(rt, "viewer");
        server.onSpectatorConnect(rt, "viewer").block();
        var snapshot = frames.getFirst().payload();
        assertThat(snapshot).containsKeys("phase", "round", "players", "alive");
        assertThat(snapshot).doesNotContainKeys("yourRole", "fellowTraitors", "allRoles", "nightPicks",
                "yourNightTarget", "yourVote", "canAccuse", "blackmailIntel");
    }

    @Test void spectatorsReactAtATraitorsTable() throws Exception {
        var rt = table();
        rt.spectatorUserIds.add("viewer");
        var broadcasts = new ArrayList<LobbyBroadcast>();
        var subscription = rt.bus.asFlux().ofType(LobbyBroadcast.class).subscribe(broadcasts::add);
        try {
            server.handleFrame(rt, "viewer", mapper.writeValueAsString(
                    Envelope.of(MessageType.REACTION_SEND, Map.of("emoji", "😮"))), true).block();
            assertThat(broadcasts).hasSize(1);
            assertThat(broadcasts.getFirst().type()).isEqualTo("SPECTATOR_REACTION");
            assertThat(broadcasts.getFirst().data()).containsEntry("emoji", "😮").containsEntry("from", "viewer");
        } finally {
            subscription.dispose();
        }
    }

    @Test void aGameWithoutReactionsStillTurnsThemDown() throws Exception {
        var rt = new RoomRuntime(UUID.randomUUID(), "a");
        var module = new DraughtsModule();
        rt.start(module, module.initialState(List.of("a", "b"), DraughtsConfig.defaults(), RandomSource.seeded(1)), UUID.randomUUID());
        rt.spectatorUserIds.add("viewer");
        var frames = listen(rt, "viewer");
        server.handleFrame(rt, "viewer", mapper.writeValueAsString(
                Envelope.of(MessageType.REACTION_SEND, Map.of("emoji", "🔥"))), true).block();
        assertThat(frames.getLast().payload().get("code")).isEqualTo("SPECTATORS_ONLY");
    }
}
