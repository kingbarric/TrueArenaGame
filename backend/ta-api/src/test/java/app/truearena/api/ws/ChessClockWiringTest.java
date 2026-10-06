package app.truearena.api.ws;

import app.truearena.engine.GameModule;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.game.chess.ChessConfig;
import app.truearena.game.chess.ChessModule;
import app.truearena.game.whot.WhotConfig;
import app.truearena.game.whot.WhotModule;
import app.truearena.room.RoomRuntime;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * How the orchestrator feeds chess its clocks: the client never gets to say
 * how much time it has, each turn's timer is armed from the mover's own
 * clock, and the clock can't be paused. Same hand-built-runtime approach as
 * {@code GameOrchestratorPauseResumeTest}.
 */
class ChessClockWiringTest {

    private final GameOrchestrator server = new GameOrchestrator(null, null, null, null, null,
            null, null, null, null, null, null, null, new ObjectMapper(), null);

    private RoomRuntime chessRoom(ChessConfig config) {
        var rt = new RoomRuntime(UUID.randomUUID(), "w");
        rt.config = config;
        var module = new ChessModule();
        rt.start(module, module.initialState(List.of("w", "b"), config, RandomSource.seeded(3)), UUID.randomUUID());
        rt.connectedUserIds.add("w");
        rt.connectedUserIds.add("b");
        return rt;
    }

    private void reschedule(RoomRuntime rt) throws Exception {
        Method m = GameOrchestrator.class.getDeclaredMethod("rescheduleTimer", RoomRuntime.class);
        m.setAccessible(true);
        m.invoke(server, rt);
    }

    @Test
    void theClientsOwnClockClaimIsDiscardedAndReplacedWithTheServersMeasurement() {
        RoomRuntime rt = chessRoom(ChessConfig.defaults());
        rt.timerDeadlineMs = System.currentTimeMillis() + 30_000;

        Map<String, Object> data = server.serverActionData(rt,
                Map.of("from", "e2", "to", "e4", GameModule.CLOCK_REMAINING_KEY, 9_999_999L, "__anything", 1));

        assertThat(data).containsEntry("from", "e2").doesNotContainKey("__anything");
        assertThat((Long) data.get(GameModule.CLOCK_REMAINING_KEY)).isBetween(29_000L, 30_000L);
    }

    @Test
    void gamesWithoutPlayerClocksGetNoStampButStillLoseReservedKeys() {
        var rt = new RoomRuntime(UUID.randomUUID(), "a");
        rt.config = WhotConfig.defaults();
        var module = new WhotModule();
        var state = module.initialState(List.of("a", "b"), rt.config, RandomSource.seeded(8));
        state = module.onPlayerAction(state, PlayerAction.of("a", "DEAL", Map.of("rounds", 5)));
        rt.start(module, state, UUID.randomUUID());
        rt.timerDeadlineMs = System.currentTimeMillis() + 30_000;

        assertThat(server.serverActionData(rt, Map.of("card", "c1", GameModule.CLOCK_REMAINING_KEY, 5L)))
                .isEqualTo(Map.of("card", "c1"));
    }

    @Test
    void eachTurnIsArmedWithTheMoversOwnRemainingTime() throws Exception {
        RoomRuntime rt = chessRoom(new ChessConfig(300, 0));
        reschedule(rt);
        long armedFor = rt.timerDeadlineMs - System.currentTimeMillis();
        assertThat(armedFor).isBetween(299_000L, 300_000L);

        // White spends time; black's turn is armed with black's full clock,
        // and white's clock keeps what the server measured.
        Map<String, Object> data = server.serverActionData(rt, Map.of("from", "e2", "to", "e4"));
        data.put(GameModule.CLOCK_REMAINING_KEY, 241_000L);
        rt.setState(rt.module().onPlayerAction(rt.state(), new PlayerAction("m1", "w", "MOVE", data)));
        reschedule(rt);
        assertThat(rt.timerDeadlineMs - System.currentTimeMillis()).isBetween(299_000L, 300_000L);
        assertThat(rt.module().broadcastState(rt.state()).data()).containsEntry("whiteMs", 241_000L);
        rt.cancelTimer();
    }

    @Test
    void pausingFreezesTheMoversClockAndResumingPicksItBackUp() throws Exception {
        RoomRuntime rt = chessRoom(new ChessConfig(300, 0));
        reschedule(rt);
        Method toggle = GameOrchestrator.class.getDeclaredMethod("togglePause", RoomRuntime.class, String.class);
        toggle.setAccessible(true);

        ((reactor.core.publisher.Mono<?>) toggle.invoke(server, rt, "w")).block();
        assertThat(rt.paused).isTrue();
        long frozen = server.liveClockMs(rt).orElseThrow();
        Thread.sleep(120);
        assertThat(server.liveClockMs(rt).orElseThrow()).as("no time passes while paused").isEqualTo(frozen);

        ((reactor.core.publisher.Mono<?>) toggle.invoke(server, rt, "b")).block();
        assertThat(rt.paused).isFalse();
        assertThat(server.liveClockMs(rt).orElseThrow()).isBetween(frozen - 100, frozen);
        rt.cancelTimer();
    }

    @Test
    void hostTimeControlIsReadFromTheRoomConfig() {
        assertThat(server.chessConfigFrom("{\"initialSeconds\":180,\"incrementSeconds\":2}"))
                .isEqualTo(new ChessConfig(180, 2));
        assertThat(server.chessConfigFrom(null)).isEqualTo(ChessConfig.defaults());
        assertThat(server.chessConfigFrom("{\"initialSeconds\":5}")).as("out of range falls back").isEqualTo(ChessConfig.defaults());
    }
}
