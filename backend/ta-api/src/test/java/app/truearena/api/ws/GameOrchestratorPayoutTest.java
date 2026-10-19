package app.truearena.api.ws;

import app.truearena.api.coins.CoinService;
import app.truearena.api.bot.BotRuntimeRegistry;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.room.RoomRuntime;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Flux;
import org.springframework.test.util.ReflectionTestUtils;

import java.lang.reflect.Method;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * {@code GameOrchestrator.payoutStake}/{@code awardCoins} — the coin-movement half of
 * {@code finishGame}, currently untested. Reflection-invoked directly on a hand-built
 * runtime/room, same bias toward bypassing the lock-guarded entry points as the other
 * {@code GameOrchestrator*Test} classes in this package.
 */
class GameOrchestratorPayoutTest {

    private final UserRepository users = mock(UserRepository.class);
    private final RoomMemberRepository members = mock(RoomMemberRepository.class);
    private final CoinService coins = mock(CoinService.class);
    private final GameOrchestrator server = new GameOrchestrator(null, null, null, null, members,
            null, null, null, null, null, users, null, null, coins);

    private UserRow human(UUID id) {
        return new UserRow(id, "Player", null, null, null, null, false, null, false, null, null, null, null, null);
    }

    private UserRow bot(UUID id, String difficulty) {
        return new UserRow(id, "Bot", null, null, null, null, false, null, true, null, null, difficulty, null, null);
    }

    @SuppressWarnings("unchecked")
    private void invokeAwardCoins(RoomRuntime rt, Map<String, String> outcome) throws Exception {
        Method m = GameOrchestrator.class.getDeclaredMethod("awardCoins", RoomRuntime.class, Map.class);
        m.setAccessible(true);
        ((Mono<Void>) m.invoke(server, rt, outcome)).block();
    }

    @SuppressWarnings("unchecked")
    private void invokeReleaseAgents(UUID roomId) throws Exception {
        Method m = GameOrchestrator.class.getDeclaredMethod("releaseAgents", UUID.class);
        m.setAccessible(true);
        ((Mono<Void>) m.invoke(server, roomId)).block();
    }

    private RoomRow stakedRoom(UUID host, long stake) {
        return new RoomRow(UUID.randomUUID(), "123456", null, host, "ended", "truearena", stake, null, false, null);
    }

    @Test
    void completedGameStopsAndDetachesItsAgents() throws Exception {
        UUID roomId = UUID.randomUUID();
        UUID humanId = UUID.randomUUID();
        UUID agentId = UUID.randomUUID();
        BotRuntimeRegistry botRuntimes = mock(BotRuntimeRegistry.class);
        ReflectionTestUtils.setField(server, "botRuntimes", botRuntimes);
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, humanId, null),
                RoomMemberRow.of(roomId, agentId, "Agent")));
        when(users.findById(humanId)).thenReturn(Mono.just(human(humanId)));
        when(users.findById(agentId)).thenReturn(Mono.just(bot(agentId, "medium")));
        when(members.deleteByRoomIdAndUserId(roomId, agentId)).thenReturn(Mono.empty());

        invokeReleaseAgents(roomId);

        verify(botRuntimes).stop(roomId, agentId);
        verify(members).deleteByRoomIdAndUserId(roomId, agentId);
        verify(members, never()).deleteByRoomIdAndUserId(roomId, humanId);
    }

    @Test
    void rewardsUsePersistentSettlementAndNeverDebitPlayers() throws Exception {
        var rewards=mock(app.truearena.api.coins.MatchRewardService.class);
        ReflectionTestUtils.setField(server,"matchRewards",rewards);
        RoomRuntime rt=mock(RoomRuntime.class);
        when(rewards.award(rt.gameSessionId)).thenReturn(Flux.empty());
        invokeAwardCoins(rt, Map.of());
        verify(rewards).award(rt.gameSessionId);
        verifyNoInteractions(coins);
    }
}
