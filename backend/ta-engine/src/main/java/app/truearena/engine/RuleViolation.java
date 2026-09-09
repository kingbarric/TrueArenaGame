package app.truearena.engine;

/** Thrown by a module when an action isn't legal in the current state. The transport turns it into an ERROR frame. */
public class RuleViolation extends RuntimeException {

    private final String code;

    public RuleViolation(String code, String message) {
        super(message);
        this.code = code;
    }

    public String code() {
        return code;
    }
}
