package app.truearena.api.calls;

public final class CallDtos {

    private CallDtos() {
    }

    public record CallToken(String roomName, String token, String livekitUrl) {
    }
}
