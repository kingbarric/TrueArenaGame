package app.truearena.api.ws;

import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.room.LobbyBroadcast;
import app.truearena.room.RoomRuntime;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.argThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * {@code GameOrchestrator.migrateHost} — the "host disconnected for 10s" path
 * (see {@code onDisconnect}). Bypasses the lock/persistence-heavy entry points
 * entirely (same bias as {@code WhotSpectatorTest}/{@code WhotTurnTimerTest}) by
 * invoking the private reducer directly via reflection on a hand-built runtime.
 */
class GameOrchestratorHostMigrationTest {

    private final RoomRepository rooms = mock(RoomRepository.class);
    private final UserRepository users = mock(UserRepository.class);
    private final GameOrchestrator server = new GameOrchestrator(null, null, null, rooms, null,
            null, null, null, null, null, users, null, null, null);

    private RoomRuntime table(UUID hostId) {
        return new RoomRuntime(UUID.randomUUID(), hostId.toString());
    }

    private UserRow human(UUID id) {
        return new UserRow(id, "Player", null, null, null, null, false, null, false, null, null, null, null, null);
    }

    private UserRow bot(UUID id) {
        return new UserRow(id, "Bot", null, null, null, null, false, null, true, null, null, "easy", null, null);
    }

    @SuppressWarnings("unchecked")
    private void invokeMigrateHost(RoomRuntime rt) throws Exception {
        Method method = GameOrchestrator.class.getDeclaredMethod("migrateHost", RoomRuntime.class);
        method.setAccessible(true);
        ((Mono<Void>) method.invoke(server, rt)).block();
    }

    @Test
    void picksTheFirstConnectedHumanNotABot() throws Exception {
        UUID oldHost = UUID.randomUUID();
        UUID botId = UUID.randomUUID();
        UUID humanId = UUID.randomUUID();
        RoomRuntime rt = table(oldHost);
        rt.connectedUserIds.add(botId.toString());
        rt.connectedUserIds.add(humanId.toString());

        when(users.findById(botId)).thenReturn(Mono.just(bot(botId)));
        when(users.findById(humanId)).thenReturn(Mono.just(human(humanId)));
        RoomRow room = new RoomRow(rt.roomId, "123456", null, oldHost, "lobby", "truearena", 0L, null, null);
        when(rooms.findById(rt.roomId)).thenReturn(Mono.just(room));
        when(rooms.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));

        List<Object> frames = new ArrayList<>();
        var sub = rt.bus.asFlux().subscribe(frames::add);
        try {
            invokeMigrateHost(rt);
        } finally {
            sub.dispose();
        }

        assertThat(rt.hostUserId).isEqualTo(humanId.toString());
        verify(rooms).save(argThat(r -> humanId.equals(((RoomRow) r).hostId())));
        assertThat(frames).anyMatch(f -> f instanceof LobbyBroadcast lb
                && "HOST_CHANGED".equals(lb.type()) && humanId.toString().equals(lb.data().get("hostId")));
    }

    @Test
    void staysPutWhenOnlyBotsRemainConnected() throws Exception {
        UUID oldHost = UUID.randomUUID();
        UUID botId = UUID.randomUUID();
        RoomRuntime rt = table(oldHost);
        rt.connectedUserIds.add(botId.toString());
        when(users.findById(botId)).thenReturn(Mono.just(bot(botId)));

        invokeMigrateHost(rt);

        assertThat(rt.hostUserId).isEqualTo(oldHost.toString());
        verifyNoInteractions(rooms);
    }

    @Test
    void staysPutWhenNobodyIsConnected() throws Exception {
        UUID oldHost = UUID.randomUUID();
        RoomRuntime rt = table(oldHost);

        invokeMigrateHost(rt);

        assertThat(rt.hostUserId).isEqualTo(oldHost.toString());
        verifyNoInteractions(rooms, users);
    }
}
