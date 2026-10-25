package app.truearena.api.ws;

import app.truearena.persistence.*;
import app.truearena.room.RoomEventLog;
import app.truearena.room.RoomLock;
import app.truearena.room.RoomRuntime;
import app.truearena.ws.contract.Envelope;
import app.truearena.ws.contract.MessageType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class WhotTellBotStartTest {
    @SuppressWarnings("unchecked")
    @Test void aHumanHostCanStartTheTellWithThreeCyberAgents() throws Exception {
        var rooms = mock(RoomRepository.class); var members = mock(RoomMemberRepository.class);
        var sessions = mock(GameSessionRepository.class); var users = mock(UserRepository.class);
        var lock = mock(RoomLock.class); var log = mock(RoomEventLog.class);
        var mapper = new ObjectMapper(); var roomId = UUID.randomUUID(); var host = UUID.randomUUID();
        var botIds = List.of(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID());
        var room = new RoomRow(roomId, "AB12CD", null, host, "lobby", "whot", 0, "{\"mode\":\"tell\"}", false, null);
        when(lock.withLock(any(), any(), any())).thenAnswer(call -> ((Supplier<Mono<?>>) call.getArgument(2)).get());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(rooms.save(any(RoomRow.class))).thenAnswer(call -> Mono.just(call.getArgument(0)));
        when(members.findByRoomId(roomId)).thenReturn(Flux.concat(
                Flux.just(RoomMemberRow.of(roomId, host, "Host")),
                Flux.fromIterable(botIds).map(id -> RoomMemberRow.bot(roomId, id, "Cyber", "hard"))));
        var session = mock(GameSessionRow.class); when(session.id()).thenReturn(UUID.randomUUID());
        when(sessions.save(any(GameSessionRow.class))).thenReturn(Mono.just(session));
        when(log.append(any(), any())).thenReturn(Mono.empty());
        var server = new GameOrchestrator(null, lock, log, rooms, members, sessions,
                null, null, null, null, users, null, mapper, null);
        var runtime = new RoomRuntime(roomId, host.toString());
        try {
            server.handleFrame(runtime, host.toString(), mapper.writeValueAsString(
                    Envelope.of(MessageType.GAME_START, Map.of())), false).block();
            assertThat(runtime.started()).isTrue();
            assertThat(runtime.state().phase()).isEqualTo("Signals");
            assertThat(runtime.botPlayerIds).containsExactlyInAnyOrderElementsOf(botIds.stream().map(UUID::toString).toList());
            assertThat(runtime.module().visibleStateFor(runtime.state(), botIds.getFirst().toString()).data())
                    .containsKeys("yourSignal", "yourSignalConfirmed", "yourTeam");
        } finally { runtime.cancelTimer(); }
    }
}
