package app.truearena.engine;

import java.util.Map;

/**
 * A move from one player (or the host). {@code actionId} is client-generated and used
 * for idempotency — replaying it after a reconnect is a no-op.
 */
public record PlayerAction(String actionId, String actor, String type, Map<String, Object> data) {

    public PlayerAction {
        if (data == null) {
            data = Map.of();
        }
    }

    public String str(String key) {
        Object v = data.get(key);
        return v == null ? null : v.toString();
    }

    public static PlayerAction of(String actor, String type, Map<String, Object> data) {
        return new PlayerAction(java.util.UUID.randomUUID().toString(), actor, type, data);
    }
}
