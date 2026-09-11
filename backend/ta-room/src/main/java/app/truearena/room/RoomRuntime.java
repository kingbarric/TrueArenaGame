package app.truearena.room;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameModule;
import app.truearena.engine.GameState;
import reactor.core.Disposable;
import reactor.core.publisher.Sinks;

import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * One live room, held in memory on whichever pod is serving it (single-pod for v1 —
 * see docs/PROJECT_PLAN.md Phase 4 status for the multi-pod gap). Nothing here is
 * game-specific: the module/state are only set once a game actually starts.
 */
public final class RoomRuntime {

    public final UUID roomId;
    public volatile String hostUserId;

    private volatile GameModule module;
    private volatile GameState state;
    private volatile Map<String, String> roleByUser = Map.of();
    public volatile UUID gameSessionId;
    public volatile GameConfig config;

    /** Fan-out to every connected socket: {@link GameEvent} (filtered per viewer) or {@link LobbyBroadcast} (always public). */
    public final Sinks.Many<Object> bus = Sinks.many().multicast().onBackpressureBuffer();

    /** Private replies (SNAPSHOT, ERROR, PONG) — latest connection per user wins. */
    public final Map<String, Sinks.Many<Object>> unicast = new ConcurrentHashMap<>();

    public final Set<String> connectedUserIds = ConcurrentHashMap.newKeySet();

    public volatile Disposable timer;
    public volatile String timerForPhase;

    public RoomRuntime(UUID roomId, String hostUserId) {
        this.roomId = roomId;
        this.hostUserId = hostUserId;
    }

    public boolean started() {
        return module != null;
    }

    public GameModule module() {
        return module;
    }

    public GameState state() {
        return state;
    }

    public void start(GameModule module, GameState state, UUID gameSessionId) {
        this.module = module;
        this.state = state;
        this.gameSessionId = gameSessionId;
    }

    public void setState(GameState state) {
        this.state = state;
    }

    public Map<String, String> roleByUser() {
        return roleByUser;
    }

    public void setRoleByUser(Map<String, String> roleByUser) {
        this.roleByUser = roleByUser;
    }

    public void tellUser(String userId, Object message) {
        Sinks.Many<Object> sink = unicast.get(userId);
        if (sink != null) {
            sink.tryEmitNext(message);
        }
    }

    public void cancelTimer() {
        if (timer != null) {
            timer.dispose();
        }
        timer = null;
        timerForPhase = null;
    }
}
