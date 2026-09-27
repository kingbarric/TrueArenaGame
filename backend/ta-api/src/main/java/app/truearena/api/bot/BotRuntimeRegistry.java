package app.truearena.api.bot;

import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/** Live {@link BotRuntime}s, keyed by the bot's own user id — one pod, in-memory,
 * same v1 scope as {@code RoomRuntimeRegistry} (see docs/DEV_REFERENCE.md Phase 4). */
@Component
public class BotRuntimeRegistry {

    private final Map<UUID, BotRuntime> byBotId = new ConcurrentHashMap<>();

    public void register(UUID botId, BotRuntime runtime) {
        BotRuntime previous = byBotId.put(botId, runtime);
        if (previous != null) {
            previous.stop();
        }
    }

    public void stop(UUID botId) {
        BotRuntime runtime = byBotId.remove(botId);
        if (runtime != null) {
            runtime.stop();
        }
    }
}
