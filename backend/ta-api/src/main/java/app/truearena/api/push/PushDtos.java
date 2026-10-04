package app.truearena.api.push;

import jakarta.validation.constraints.NotBlank;

public class PushDtos {
    private PushDtos() {
    }

    public record RegisterDeviceTokenRequest(@NotBlank String platform, @NotBlank String token) {
    }

    public record UnregisterDeviceTokenRequest(@NotBlank String token) {
    }
}
