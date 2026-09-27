package app.truearena.engine;

/**
 * A named phase in the round loop. {@code timerSeconds} &lt;= 0 means host- or
 * logic-advanced.
 *
 * <p>{@code startsPaused} marks a phase whose clock must not start on its
 * own: entering it suspends the room, and the countdown only begins when a
 * player resumes. That's what a grace period is — time offered to someone
 * who has stepped away, which would be pointless if it drained while they
 * were still away (see {@code DraughtsModule}'s Grace phases).
 */
public record Phase(String name, int timerSeconds, boolean startsPaused) {

    public Phase(String name, int timerSeconds) {
        this(name, timerSeconds, false);
    }

    public boolean timed() {
        return timerSeconds > 0;
    }

    public static Phase untimed(String name) {
        return new Phase(name, 0, false);
    }

    /** A timed phase that waits, paused, for a player to resume before its clock starts. */
    public static Phase awaitingResume(String name, int timerSeconds) {
        return new Phase(name, timerSeconds, true);
    }
}
