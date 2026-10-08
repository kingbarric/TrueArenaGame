package app.truearena.room;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameModule;
import app.truearena.engine.GameSettings;
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
    public final java.util.Set<String> botPlayerIds = new java.util.HashSet<>();

    public final UUID roomId;
    public volatile String hostUserId;

    private volatile GameModule module;
    private volatile GameState state;
    private volatile Map<String, String> roleByUser = Map.of();
    public volatile UUID gameSessionId;
    public volatile GameSettings config;

    /** Fan-out to every connected socket: {@link GameEvent} (filtered per viewer) or {@link LobbyBroadcast} (always public). */
    public final Sinks.Many<Object> bus = Sinks.many().multicast().onBackpressureBuffer();

    /** Private replies (SNAPSHOT, ERROR, PONG) — latest connection per user wins. */
    public final Map<String, Sinks.Many<Object>> unicast = new ConcurrentHashMap<>();

    public final Set<String> connectedUserIds = ConcurrentHashMap.newKeySet();

    /** Read-only viewers — never in {@link #connectedUserIds}, never gated by room membership. */
    public final Set<String> spectatorUserIds = ConcurrentHashMap.newKeySet();

    /** Room-level, not game-state — a pause is a transport/UI concern, not something any {@code GameModule} needs to know about. */
    public volatile boolean paused;
    /** Social ownership is immutable; legacy room host migration does not apply. */
    public volatile boolean socialHuud;
    public volatile boolean cancelled;
    public final Set<String> revokedUserIds = ConcurrentHashMap.newKeySet();
    public void revoke(String userId) {
        revokedUserIds.add(userId);
        Sinks.Many<Object> sink=unicast.get(userId);
        if(sink!=null) sink.tryEmitError(new SecurityException("Huud access removed"));
    }
    /** Tournament clocks are controlled by reconnect policy, not a player's pause button. */
    public volatile boolean tournament;

    /** Any player can mute the spectate-channel comments (see {@code GameOrchestrator.handleMuteSpectatorsToggle}). */
    public volatile boolean spectatorsMuted;

    /** Spectators waiting for a player to admit them to the live voice room. */
    public final Set<String> spectatorVoiceRequests = ConcurrentHashMap.newKeySet();

    /** Spectators currently allowed to mint a token for the live voice room. */
    public final Set<String> spectatorVoiceSpeakers = ConcurrentHashMap.newKeySet();

    /** Approved speakers whose publish permission has been suspended by a player. */
    public final Set<String> mutedSpectatorVoiceSpeakers = ConcurrentHashMap.newKeySet();

    public volatile Disposable timer;
    public volatile String timerForPhase;
    public volatile int timerForRound;

    /**
     * When the running phase timer is due to fire (epoch millis), or 0 if no
     * timer is armed. Kept so a pause can work out how much time was left
     * and a resume can re-arm for exactly that much, instead of the turn
     * silently restarting from full — or, worse, expiring while paused.
     */
    public volatile long timerDeadlineMs;

    /** Millis left on the clock at the moment of pausing; 0 when not paused. */
    public volatile long timerRemainingMs;

    /**
     * The last set of player ids a turn-reminder push was sent for, so
     * repeated sub-events while the same player is still on turn (e.g. a
     * capture chain) don't re-notify every time. Reset whenever the set of
     * players-to-act actually changes — see {@code GameOrchestrator.pushTurnReminders}.
     */
    public volatile Set<String> lastNotifiedTurnFor = Set.of();

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
