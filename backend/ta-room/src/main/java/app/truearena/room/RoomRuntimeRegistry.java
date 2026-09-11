package app.truearena.room;

import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;

/** In-memory registry of live {@link RoomRuntime}s on this pod. */
@Component
public class RoomRuntimeRegistry {

    private final Map<UUID, RoomRuntime> rooms = new ConcurrentHashMap<>();

    public RoomRuntime computeIfAbsent(UUID roomId, Function<UUID, RoomRuntime> factory) {
        return rooms.computeIfAbsent(roomId, factory);
    }

    public Optional<RoomRuntime> find(UUID roomId) {
        return Optional.ofNullable(rooms.get(roomId));
    }

    public void remove(UUID roomId) {
        rooms.remove(roomId);
    }
}
