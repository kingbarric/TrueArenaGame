package app.truearena.room;

import java.util.Map;

/**
 * A non-engine, always-public message about the room itself (ready-check, host
 * migration, …) — flows through the same {@link RoomRuntime#bus} as engine
 * {@code GameEvent}s so one subscription pipeline serves both.
 */
public record LobbyBroadcast(String type, Map<String, Object> data) {
}
