package app.truearena.api.bot;

import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/** Live {@link BotRuntime}s, isolated by room and system-agent identity. */
@Component
public class BotRuntimeRegistry {

    private record RuntimeKey(UUID roomId, UUID botId) {}

    private final Map<RuntimeKey, BotRuntime> runtimes = new ConcurrentHashMap<>();

    public void register(UUID roomId, UUID botId, BotRuntime runtime) {
        BotRuntime previous = runtimes.put(new RuntimeKey(roomId, botId), runtime);
        if (previous != null) {
            previous.stop();
        }
    }

    public void stop(UUID roomId, UUID botId) {
        BotRuntime runtime = runtimes.remove(new RuntimeKey(roomId, botId));
        if (runtime != null) {
            runtime.stop();
        }
    }

    public void stopRoom(UUID roomId) {
        runtimes.keySet().stream()
                .filter(key -> key.roomId().equals(roomId))
                .toList()
                .forEach(key -> {
                    BotRuntime runtime = runtimes.remove(key);
                    if (runtime != null) runtime.stop();
                });
    }
}
