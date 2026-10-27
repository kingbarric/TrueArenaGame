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

    @SuppressWarnings("unchecked")
    @Test void aSpectatorsCrowdVoteReachesTheGame_butNoOtherGameAction() throws Exception {
        var lock = org.mockito.Mockito.mock(app.truearena.room.RoomLock.class);
        org.mockito.Mockito.when(lock.withLock(org.mockito.ArgumentMatchers.any(), org.mockito.ArgumentMatchers.any(),
                org.mockito.ArgumentMatchers.any())).thenAnswer(call -> ((java.util.function.Supplier<reactor.core.publisher.Mono<?>>) call.getArgument(2)).get());
        var log = org.mockito.Mockito.mock(app.truearena.room.RoomEventLog.class);
        org.mockito.Mockito.when(log.append(org.mockito.ArgumentMatchers.any(), org.mockito.ArgumentMatchers.any()))
                .thenReturn(reactor.core.publisher.Mono.empty());
        var live = new GameOrchestrator(null, lock, log, null, null, null, null, null, null, null, null, null, mapper, null);
        var rt = table();
        rt.setState(rt.module().onPhaseElapsed(rt.state(), "RoleReveal")); // night falls: the crowd can weigh in
        rt.spectatorUserIds.add("viewer");
        var frames = listen(rt, "viewer");

        live.handleFrame(rt, "viewer", mapper.writeValueAsString(Envelope.of(MessageType.PLAYER_ACTION,
                Map.of("action", "CROWD_VOTE", "data", Map.of("target", "p3")))), true).block();
        assertThat((Map<String, Object>) rt.module().broadcastState(rt.state()).data().get("crowdHunch"))
                .containsEntry("voters", 1);

        var before = rt.state();
        live.handleFrame(rt, "viewer", mapper.writeValueAsString(Envelope.of(MessageType.PLAYER_ACTION,
                Map.of("action", "CAST_VOTE", "data", Map.of("target", "p3")))), true).block();
        assertThat(frames.getLast().payload().get("code")).isEqualTo("SPECTATOR_READ_ONLY");
        assertThat(rt.state()).isSameAs(before);

        rt.tournament = true;
        live.handleFrame(rt, "viewer", mapper.writeValueAsString(Envelope.of(MessageType.PLAYER_ACTION,
                Map.of("action", "CROWD_VOTE", "data", Map.of("target", "p4")))), true).block();
        assertThat(frames.getLast().payload().get("code")).as("championships stay read-only").isEqualTo("SPECTATOR_READ_ONLY");
    }

    @Test void aGameWithoutReactionsStillTurnsThemDown() throws Exception {
        var rt = new RoomRuntime(UUID.randomUUID(), "a");
        var module = new app.truearena.game.chess.ChessModule();
        rt.start(module, module.initialState(List.of("a", "b"), app.truearena.game.chess.ChessConfig.defaults(), RandomSource.seeded(1)), UUID.randomUUID());
        rt.spectatorUserIds.add("viewer");
        var frames = listen(rt, "viewer");
        server.handleFrame(rt, "viewer", mapper.writeValueAsString(
                Envelope.of(MessageType.REACTION_SEND, Map.of("emoji", "🔥"))), true).block();
        assertThat(frames.getLast().payload().get("code")).isEqualTo("SPECTATORS_ONLY");
    }
}
