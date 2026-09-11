package app.truearena.room;

/** Marker pushed on {@link RoomRuntime#bus} whenever the engine phase advances. */
public record PhaseChanged(String phase, int round) {
}
