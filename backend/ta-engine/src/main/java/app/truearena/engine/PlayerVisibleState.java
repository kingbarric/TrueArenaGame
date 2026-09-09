package app.truearena.engine;

import java.util.Map;

/** The per-subscriber projection {@code ta-ws} sends after fan-out. Filtered server-side. */
public record PlayerVisibleState(Map<String, Object> data) {
}
