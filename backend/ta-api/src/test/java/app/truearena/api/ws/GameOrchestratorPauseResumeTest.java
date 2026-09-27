package app.truearena.api.ws;

import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.game.whot.WhotConfig;
import app.truearena.game.whot.WhotModule;
import app.truearena.room.RoomRuntime;
import org.junit.jupiter.api.Test;
import reactor.core.Disposable;

import java.lang.reflect.Method;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@code GameOrchestrator.freezeTimer}/{@code thawTimer}/{@code secondsLeft} — the
 * pause/resume banked-timer math. Same reflection-invoke pattern as
 * {@code WhotTurnTimerTest.aNewWhotTurnReplacesTheClockButARepeatedSnapshotDoesNot}
 * (which covers {@code rescheduleTimer}'s non-paused branches); this covers the
 * paused ones plus the two methods {@code handlePauseToggle} delegates to.
 */
class GameOrchestratorPauseResumeTest {

    private final GameOrchestrator server = new GameOrchestrator(null, null, null, null, null,
            null, null, null, null, null, null, null, null, null);

    private RoomRuntime startedRoom() {
        var rt = new RoomRuntime(UUID.randomUUID(), "a");
        rt.config = WhotConfig.defaults();
        var module = new WhotModule();
        var state = module.initialState(List.of("a", "b"), rt.config, RandomSource.seeded(8));
        state = module.onPlayerAction(state, PlayerAction.of("a", "DEAL", Map.of("rounds", 5)));
        state = module.onPlayerAction(state, PlayerAction.of("a", "START", Map.of()));
        rt.start(module, state, UUID.randomUUID());
        return rt;
    }

    private void invokeVoid(String name, RoomRuntime rt) throws Exception {
        Method m = GameOrchestrator.class.getDeclaredMethod(name, RoomRuntime.class);
        m.setAccessible(true);
        m.invoke(server, rt);
    }

    private int invokeSecondsLeft(RoomRuntime rt) throws Exception {
        Method m = GameOrchestrator.class.getDeclaredMethod("secondsLeft", RoomRuntime.class);
        m.setAccessible(true);
        return (int) m.invoke(server, rt);
    }

    @Test
    void freezeTimer_banksWhateverWasLeftAndCancelsTheLiveTimer() throws Exception {
        RoomRuntime rt = startedRoom();
        rt.timerDeadlineMs = System.currentTimeMillis() + 30_000;
        Disposable live = reactor.core.publisher.Mono.never().subscribe();
        rt.timer = live;

        invokeVoid("freezeTimer", rt);

        assertThat(rt.timerRemainingMs).isGreaterThan(29_000).isLessThanOrEqualTo(30_000);
        assertThat(rt.timer).isNull();
        assertThat(live.isDisposed()).isTrue();
        assertThat(rt.timerForPhase).isEqualTo(rt.state().phase());
    }

    @Test
    void thawTimer_reArmsForExactlyTheBankedRemainder() throws Exception {
        RoomRuntime rt = startedRoom();
        rt.timerRemainingMs = 5_000;

        invokeVoid("thawTimer", rt);

        assertThat(rt.timerRemainingMs).isZero(); // consumed on thaw
        assertThat(rt.timer).isNotNull();
        assertThat(rt.timer.isDisposed()).isFalse();
        assertThat(rt.timerForPhase).isEqualTo(rt.state().phase());
        assertThat(rt.timerForRound).isEqualTo(rt.state().round());
        assertThat(rt.timerDeadlineMs - System.currentTimeMillis()).isGreaterThan(4_000).isLessThanOrEqualTo(5_000);
        rt.cancelTimer();
    }

    @Test
    void thawTimer_noOpsWhenNothingWasBanked() throws Exception {
        RoomRuntime rt = startedRoom();
        rt.timerRemainingMs = 0;

        invokeVoid("thawTimer", rt);

        assertThat(rt.timer).isNull();
    }

    @Test
    void secondsLeft_reflectsTheFrozenValueWhilePaused() throws Exception {
        RoomRuntime rt = startedRoom();
        rt.paused = true;
        rt.timerRemainingMs = 12_345;

        assertThat(invokeSecondsLeft(rt)).isEqualTo(12);
    }

    @Test
    void secondsLeft_isALiveCountdownWhenNotPaused() throws Exception {
        RoomRuntime rt = startedRoom();
        rt.paused = false;
        rt.timerDeadlineMs = System.currentTimeMillis() + 7_000;

        assertThat(invokeSecondsLeft(rt)).isBetween(6, 7);
    }
}
