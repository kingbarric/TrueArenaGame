package app.truearena.ws.contract;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.util.Map;

/**
 * The single WebSocket frame envelope (Architecture §3.2). {@code seq} is null on most
 * client frames; {@code payload} shape is defined per {@link MessageType} in later phases.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record Envelope(
        int v,
        MessageType type,
        Long seq,
        long ts,
        Map<String, Object> payload
) {
    public static final int VERSION = 1;

    public static Envelope of(MessageType type, Map<String, Object> payload) {
        return new Envelope(VERSION, type, null, System.currentTimeMillis(), payload);
    }
}
