package app.truearena.api.ws;

import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.game.whot.WhotConfig;
import app.truearena.game.whot.WhotModule;
import app.truearena.room.RoomRuntime;
import org.junit.jupiter.api.Test;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import static org.assertj.core.api.Assertions.assertThat;

class WhotTurnTimerTest {
    @Test
    void aNewWhotTurnReplacesTheClockButARepeatedSnapshotDoesNot() throws Exception {
        var orchestrator = new GameOrchestrator(null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);
        var method = GameOrchestrator.class.getDeclaredMethod("rescheduleTimer", RoomRuntime.class);
        method.setAccessible(true);
        var module = new WhotModule();
        var rt = new RoomRuntime(UUID.randomUUID(), "a");
        rt.config = WhotConfig.defaults();
        var state = module.initialState(List.of("a", "b"), rt.config, RandomSource.seeded(8));
        state = module.onPlayerAction(state, PlayerAction.of("a", "DEAL", Map.of("rounds", 5)));
        state = module.onPlayerAction(state, PlayerAction.of("a", "START", Map.of()));
        rt.start(module, state, UUID.randomUUID());
        try {
            method.invoke(orchestrator, rt);
            var oldTimer = rt.timer;
            method.invoke(orchestrator, rt);
            assertThat(rt.timer).isSameAs(oldTimer);
            rt.setState(module.onPlayerAction(rt.state(), PlayerAction.of("a", "DRAW", Map.of())));
            method.invoke(orchestrator, rt);
            assertThat(oldTimer.isDisposed()).isTrue();
            assertThat(rt.timer).isNotSameAs(oldTimer);
            assertThat(rt.timerForRound).isEqualTo(rt.state().round());
            assertThat(rt.timerDeadlineMs - System.currentTimeMillis()).isGreaterThan(44000);
        } finally {
            rt.cancelTimer();
        }
    }
}
