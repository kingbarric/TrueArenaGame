package app.truearena.engine;

import java.util.Map;

/** The stream-safe projection for Track B's host display. Never carries secret roles pre-reveal. */
public record PublicBroadcastState(Map<String, Object> data) {
}
