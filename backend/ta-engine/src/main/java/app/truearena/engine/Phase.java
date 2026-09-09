package app.truearena.engine;

/** A named phase in the round loop. {@code timerSeconds} <= 0 means host- or logic-advanced. */
public record Phase(String name, int timerSeconds) {

    public boolean timed() {
        return timerSeconds > 0;
    }

    public static Phase untimed(String name) {
        return new Phase(name, 0);
    }
}
