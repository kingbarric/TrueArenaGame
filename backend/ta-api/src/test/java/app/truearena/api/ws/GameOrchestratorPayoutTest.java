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
    private void invokePayoutStake(RoomRow room, Map<String, String> outcome) throws Exception {
        Method m = GameOrchestrator.class.getDeclaredMethod("payoutStake", RoomRow.class, Map.class);
        m.setAccessible(true);
        ((Mono<Void>) m.invoke(server, room, outcome)).block();
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
        return new RoomRow(UUID.randomUUID(), "123456", null, host, "ended", "truearena", stake, null, null);
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

        verify(botRuntimes).stop(agentId);
        verify(members).deleteByRoomIdAndUserId(roomId, agentId);
        verify(members, never()).deleteByRoomIdAndUserId(roomId, humanId);
    }

    // ---------------------------------------------------------------- payoutStake

    @Test
    void payoutStake_splitsThePotEvenlyWithTheRemainderToTheFirstWinner() throws Exception {
        UUID w1 = UUID.randomUUID();
        UUID w2 = UUID.randomUUID();
        UUID loser = UUID.randomUUID();
        RoomRow room = stakedRoom(w1, 5L); // pot = 5 * 3 players = 15; 2 winners -> share 7, remainder 1
        Map<String, String> outcome = new LinkedHashMap<>();
        outcome.put(w1.toString(), "won");
        outcome.put(w2.toString(), "won");
        outcome.put(loser.toString(), "lost");
        when(coins.credit(any(), anyLong(), any(), any())).thenReturn(Mono.just(0L));

        invokePayoutStake(room, outcome);

        verify(coins).credit(w1, 8L, CoinService.REASON_MATCH_STAKE_PAYOUT, room.id());
        verify(coins).credit(w2, 7L, CoinService.REASON_MATCH_STAKE_PAYOUT, room.id());
        verify(coins, never()).credit(eq(loser), anyLong(), any(), any());
    }

    @Test
    void payoutStake_noOpForAnUnstakedRoom() throws Exception {
        RoomRow room = stakedRoom(UUID.randomUUID(), 0L);
        invokePayoutStake(room, Map.of(UUID.randomUUID().toString(), "won"));
        verifyNoInteractions(coins);
    }

    @Test
    void payoutStake_noOpWhenNobodyWonOrTied() throws Exception {
        RoomRow room = stakedRoom(UUID.randomUUID(), 10L);
        invokePayoutStake(room, Map.of(UUID.randomUUID().toString(), "lost"));
        verifyNoInteractions(coins);
    }

    @Test
    void payoutStake_oneWinnersCreditFailureNeverBlocksTheOthers() throws Exception {
        UUID w1 = UUID.randomUUID();
        UUID w2 = UUID.randomUUID();
        RoomRow room = stakedRoom(w1, 10L);
        Map<String, String> outcome = new LinkedHashMap<>();
        outcome.put(w1.toString(), "won");
        outcome.put(w2.toString(), "won");
        when(coins.credit(eq(w1), anyLong(), any(), any())).thenReturn(Mono.error(new RuntimeException("boom")));
        when(coins.credit(eq(w2), anyLong(), any(), any())).thenReturn(Mono.just(0L));

        invokePayoutStake(room, outcome); // must complete without throwing

        verify(coins).credit(eq(w2), anyLong(), any(), any());
    }

    // ---------------------------------------------------------------- awardCoins

    @Test
    void awardCoins_hardestBotDifficultyAtTheTableSetsTheAgentRate() throws Exception {
        UUID player = UUID.randomUUID();
        UUID easyBot = UUID.randomUUID();
        UUID hardBot = UUID.randomUUID();
        RoomRuntime rt = new RoomRuntime(UUID.randomUUID(), player.toString());
        when(users.findById(player)).thenReturn(Mono.just(human(player)));
        when(users.findById(easyBot)).thenReturn(Mono.just(bot(easyBot, "easy")));
        when(users.findById(hardBot)).thenReturn(Mono.just(bot(hardBot, "hard")));
        when(coins.credit(eq(player), anyLong(), any(), any())).thenReturn(Mono.just(0L));

        Map<String, String> outcome = Map.of(player.toString(), "won", easyBot.toString(), "lost", hardBot.toString(), "lost");
        invokeAwardCoins(rt, outcome);

        verify(coins).credit(player, CoinService.WIN_VS_LEGEND, CoinService.REASON_MATCH_WIN, null);
        verify(coins, never()).credit(eq(easyBot), anyLong(), any(), any());
        verify(coins, never()).credit(eq(hardBot), anyLong(), any(), any());
    }

    @Test
    void awardCoins_fallsBackToPersonRatesWhenNoAgentIsPresent() throws Exception {
        UUID winner = UUID.randomUUID();
        UUID loser = UUID.randomUUID();
        RoomRuntime rt = new RoomRuntime(UUID.randomUUID(), winner.toString());
        when(users.findById(winner)).thenReturn(Mono.just(human(winner)));
        when(users.findById(loser)).thenReturn(Mono.just(human(loser)));
        when(coins.credit(any(), anyLong(), any(), any())).thenReturn(Mono.just(0L));

        invokeAwardCoins(rt, Map.of(winner.toString(), "won", loser.toString(), "lost"));

        verify(coins).credit(winner, CoinService.WIN_VS_PERSON, CoinService.REASON_MATCH_WIN, null);
        verify(coins).credit(loser, CoinService.LOSS_VS_PERSON, CoinService.REASON_MATCH_LOSS, null);
    }

    @Test
    void awardCoins_neverPaysABot() throws Exception {
        UUID player = UUID.randomUUID();
        UUID botId = UUID.randomUUID();
        RoomRuntime rt = new RoomRuntime(UUID.randomUUID(), player.toString());
        when(users.findById(player)).thenReturn(Mono.just(human(player)));
        when(users.findById(botId)).thenReturn(Mono.just(bot(botId, "medium")));
        when(coins.credit(any(), anyLong(), any(), any())).thenReturn(Mono.just(0L));

        invokeAwardCoins(rt, Map.of(player.toString(), "won", botId.toString(), "lost"));

        verify(coins, never()).credit(eq(botId), anyLong(), any(), any());
    }
}
