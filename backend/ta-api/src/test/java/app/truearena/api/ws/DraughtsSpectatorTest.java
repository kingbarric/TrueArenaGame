package app.truearena.api.ws;

import app.truearena.engine.RandomSource;
import app.truearena.game.draughts.DraughtsConfig;
import app.truearena.game.draughts.DraughtsModule;
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

class DraughtsSpectatorTest {
    private final ObjectMapper mapper = new ObjectMapper();
    private final GameOrchestrator server = new GameOrchestrator(null, null, null, null, null,
            null, null, null, null, null, null, null, mapper, null);
    @Test void reactionsAreEphemeralRateLimitedAndRespectMuteAndTournamentRules() throws Exception {
        var rt = new RoomRuntime(UUID.randomUUID(), "a");
        var module = new DraughtsModule();
        rt.start(module, module.initialState(List.of("a", "b"), DraughtsConfig.defaults(), RandomSource.seeded(1)), UUID.randomUUID());
        rt.spectatorUserIds.add("viewer");
        var sink = Sinks.many().unicast().onBackpressureBuffer();
        rt.unicast.put("viewer", sink);
        var errors = new ArrayList<Envelope>();
        var replies = sink.asFlux().cast(Envelope.class).subscribe(errors::add);
        var messages = new ArrayList<LobbyBroadcast>();
        var events = rt.bus.asFlux().ofType(LobbyBroadcast.class).subscribe(messages::add);
        var state = rt.state();
        String frame = mapper.writeValueAsString(Envelope.of(MessageType.REACTION_SEND, Map.of("emoji", "🔥")));
        try {
            server.handleFrame(rt, "viewer", frame, true).block();
            assertThat(messages).hasSize(1);
            assertThat(messages.getFirst().type()).isEqualTo("SPECTATOR_REACTION");
            server.handleFrame(rt, "viewer", frame, true).block();
            assertThat(errors.getLast().payload()).containsEntry("code", "REACTION_RATE");
            rt.spectatorsMuted = true;
            server.handleFrame(rt, "viewer", frame, true).block();
            assertThat(errors.getLast().payload()).containsEntry("code", "SPECTATORS_MUTED");
            rt.spectatorsMuted = false; rt.tournament = true;
            server.handleFrame(rt, "viewer", frame, true).block();
            assertThat(errors.getLast().payload()).containsEntry("code", "SPECTATOR_READ_ONLY");
            assertThat(messages).hasSize(1);
            assertThat(rt.state()).isSameAs(state);
        } finally { replies.dispose(); events.dispose(); rt.cancelTimer(); }
    }
    @SuppressWarnings("unchecked")
    @Test void aLiveMoveReachesSpectatorsAsEventsInsteadOfAPostMoveSnapshotBeforeThoseEvents() throws Exception {
        var log = org.mockito.Mockito.mock(app.truearena.room.RoomEventLog.class);
        org.mockito.Mockito.when(log.append(org.mockito.ArgumentMatchers.any(), org.mockito.ArgumentMatchers.any()))
                .thenReturn(reactor.core.publisher.Mono.empty());
        var lock = org.mockito.Mockito.mock(app.truearena.room.RoomLock.class);
        org.mockito.Mockito.when(lock.withLock(org.mockito.ArgumentMatchers.any(), org.mockito.ArgumentMatchers.any(), org.mockito.ArgumentMatchers.any()))
                .thenAnswer(c -> ((java.util.function.Supplier<reactor.core.publisher.Mono<?>>) c.getArgument(2)).get());
        var orchestrator = new GameOrchestrator(null, lock, log, null, null,
                null, null, null, null, null, null, null, mapper, null);
        var rt = new RoomRuntime(UUID.randomUUID(), "a");
        var module = new DraughtsModule();
        rt.config = DraughtsConfig.defaults();
        rt.start(module, module.initialState(List.of("a", "b"), rt.config, RandomSource.seeded(1)), UUID.randomUUID());
        var sink = Sinks.many().unicast().onBackpressureBuffer();
        rt.unicast.put("viewer", sink);
        var replies = new ArrayList<Envelope>();
        var sub = sink.asFlux().cast(Envelope.class).subscribe(replies::add);
        var events = new ArrayList<app.truearena.engine.GameEvent>();
        var bus = rt.bus.asFlux().ofType(app.truearena.engine.GameEvent.class).subscribe(events::add);
        try {
            orchestrator.onSpectatorConnect(rt, "viewer").block();
            assertThat(replies.getFirst().payload()).containsKeys("board", "seq", "finishEffect");
            replies.clear();
            String actor = module.broadcastState(rt.state()).data().get("playerA").toString();
            orchestrator.handleFrame(rt, actor, mapper.writeValueAsString(Envelope.of(MessageType.PLAYER_ACTION,
                    Map.of("action", "MOVE", "data", Map.of("from", 15, "to", 20)))), false).block();
            assertThat(events.stream().map(app.truearena.engine.GameEvent::type)).contains("PIECE_MOVED", "TURN_STARTED");
            assertThat(replies).noneMatch(e -> e.type() == MessageType.SNAPSHOT);
        } finally { sub.dispose(); bus.dispose(); rt.cancelTimer(); }
    }

}
