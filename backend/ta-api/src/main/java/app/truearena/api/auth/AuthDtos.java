package app.truearena.api.auth;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

import java.util.UUID;

public final class AuthDtos {

    private AuthDtos() {
    }

    public record OtpRequest(
            @NotBlank @Pattern(regexp = "\\+?[0-9]{6,15}", message = "E.164-ish digits only") String phone) {
    }

    public record OtpVerify(
            @NotBlank @Pattern(regexp = "\\+?[0-9]{6,15}") String phone,
            @NotBlank @Pattern(regexp = "[0-9]{6}") String code) {
    }

    public record RefreshRequest(@NotBlank String refreshToken) {
    }

    public record UserView(UUID id, String displayName, String phone) {
    }

    public record TokenResponse(
            String accessToken,
            String refreshToken,
            long expiresInSeconds,
            UserView user) {
    }
}
