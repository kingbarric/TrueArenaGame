package app.truearena.api.inbox;

import org.springframework.stereotype.Component;
import reactor.core.publisher.Sinks;

import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * A per-user live notification channel (`/ws/inbox`) plus who's currently
 * in which voice call — the two pieces of "presence" this app tracks today.
 * In-memory, single-pod, same v1 scope as {@code RoomRuntimeRegistry}: no
 * push when a user isn't actively connected (see docs/DEV_REFERENCE.md).
 *
 * <p>Deliberately its own small registry rather than piggybacking on
 * {@code RoomRuntime} — a call and a game room are different things (a call
 * can exist with no game room at all, e.g. before anyone's picked one), and
 * this needs to be looked up by user id globally, not scoped to one room.
 */
@Component
public class InboxRegistry {

    private final Map<UUID, Sinks.Many<Object>> sockets = new ConcurrentHashMap<>();

    /**
     * Who currently has the app backgrounded, even though their inbox socket
     * is still open — most platforms don't tear the socket down the instant
     * the app leaves the foreground. The client tells us via an
     * {@code APP_BACKGROUND}/{@code APP_FOREGROUND} frame (see
     * {@code InboxWebSocketHandler}); only {@link #isOnline} reads this, and
     * nothing else keys off it, so this is safe to be exactly as coarse as a
     * push-notification gate needs and no more.
     */
    private final Set<UUID> backgrounded = ConcurrentHashMap.newKeySet();

    /** callRoomName -> the user ids currently on that call. */
    private final Map<String, Set<UUID>> callMembers = new ConcurrentHashMap<>();
    /** The reverse index — which call (if any) a user is currently on, for O(1) lookup from a room-creator's id. */
    private final Map<UUID, String> userCallRoom = new ConcurrentHashMap<>();

    public void connect(UUID userId, Sinks.Many<Object> sink) {
        sockets.put(userId, sink);
        backgrounded.remove(userId); // a fresh connection is always made in the foreground
    }

    public void disconnect(UUID userId, Sinks.Many<Object> sink) {
        // A reconnect can replace this user's socket before the old session
        // finishes closing. Only the session still registered may clear it.
        if (sockets.remove(userId, sink)) {
            leaveCall(userId);
            backgrounded.remove(userId); // don't leak stale state into a later, unrelated connection
        }
    }

    public void setForeground(UUID userId, boolean foreground) {
        if (foreground) {
            backgrounded.remove(userId);
        } else {
            backgrounded.add(userId);
        }
    }

    /**
     * True while this user has a live, foregrounded app inbox socket on this
     * pod — i.e. would actually see a push right now without one. Used
     * exclusively by {@code PushNotificationService} to decide whether an
     * in-app live frame is enough on its own or an OS push is also needed.
     */
    public boolean isOnline(UUID userId) {
        return sockets.containsKey(userId) && !backgrounded.contains(userId);
    }

    public void joinCall(UUID userId, String callRoomName) {
        leaveCall(userId); // a user is only ever on one call at a time
        callMembers.computeIfAbsent(callRoomName, k -> ConcurrentHashMap.newKeySet()).add(userId);
        userCallRoom.put(userId, callRoomName);
    }

    public void leaveCall(UUID userId) {
        String room = userCallRoom.remove(userId);
        if (room != null) {
            Set<UUID> members = callMembers.get(room);
            if (members != null) {
                members.remove(userId);
                if (members.isEmpty()) {
                    callMembers.remove(room);
                }
            }
        }
    }

    /** Everyone currently on the same call as {@code userId}, excluding themself — empty if they're not on one. */
    public Set<UUID> callCompanionsOf(UUID userId) {
        String room = userCallRoom.get(userId);
        if (room == null) {
            return Set.of();
        }
        return callMembers.getOrDefault(room, Set.of()).stream()
                .filter(id -> !id.equals(userId))
                .collect(java.util.stream.Collectors.toUnmodifiableSet());
    }

    public void notify(UUID userId, Object payload) {
        Sinks.Many<Object> sink = sockets.get(userId);
        if (sink != null) {
            sink.tryEmitNext(payload);
        }
    }
}
