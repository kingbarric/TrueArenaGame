package app.truearena.engine;

import java.util.Map;

/** Terminal outcome. {@code winningSide} is "faithful" or "traitors". */
public record WinResult(String winningSide, Map<String, String> perPlayerOutcome) {
}
