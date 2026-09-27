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

    /** callRoomName -> the user ids currently on that call. */
    private final Map<String, Set<UUID>> callMembers = new ConcurrentHashMap<>();
    /** The reverse index — which call (if any) a user is currently on, for O(1) lookup from a room-creator's id. */
    private final Map<UUID, String> userCallRoom = new ConcurrentHashMap<>();

    public void connect(UUID userId, Sinks.Many<Object> sink) {
        sockets.put(userId, sink);
    }

    public void disconnect(UUID userId) {
        sockets.remove(userId);
        leaveCall(userId);
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
