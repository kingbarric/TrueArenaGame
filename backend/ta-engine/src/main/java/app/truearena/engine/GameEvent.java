package app.truearena.engine;

import java.util.Map;

/**
 * One entry in the append-only game log. {@code visibility} decides which subscribers
 * the {@code ta-ws} layer may forward it to — role/secret payloads are always scoped.
 */
public record GameEvent(long seq, String type, Map<String, Object> payload, Visibility visibility) {

    public static GameEvent pub(long seq, String type, Map<String, Object> payload) {
        return new GameEvent(seq, type, payload, Visibility.PUBLIC);
    }

    public static GameEvent toPlayer(long seq, String type, Map<String, Object> payload, String playerId) {
        return new GameEvent(seq, type, payload, Visibility.player(playerId));
    }

    public static GameEvent toRole(long seq, String type, Map<String, Object> payload, String role) {
        return new GameEvent(seq, type, payload, Visibility.role(role));
    }

    /** PUBLIC, or scoped to a single player id, or to everyone holding a given role. */
    public record Visibility(String scope, String key) {
        public static final Visibility PUBLIC = new Visibility("public", null);

        public static Visibility player(String id) {
            return new Visibility("player", id);
        }

        public static Visibility role(String role) {
            return new Visibility("role", role);
        }

        public boolean isPublic() {
            return "public".equals(scope);
        }
    }
}
