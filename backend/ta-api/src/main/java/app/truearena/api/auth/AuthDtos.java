package app.truearena.api.auth;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.UUID;

public final class AuthDtos {

    private AuthDtos() {
    }

    /** Exactly one of {@code phone}/{@code email} is required — checked in the controller,
     * since which one is required depends on the other (neither {@code @NotBlank} alone). */
    public record OtpRequest(
            @Pattern(regexp = "\\+?[0-9]{6,15}", message = "E.164-ish digits only") String phone,
            @Pattern(regexp = "[^@\\s]+@[^@\\s]+\\.[^@\\s]+", message = "not a valid email") String email) {
    }

    // No displayName/username here on purpose — signup is identifier-then-OTP only;
    // a username (auto-generated on account creation) is chosen afterward via
    // PATCH /me, once the client knows this is TokenResponse.newAccount.
    public record OtpVerify(
            @Pattern(regexp = "\\+?[0-9]{6,15}") String phone,
            @Pattern(regexp = "[^@\\s]+@[^@\\s]+\\.[^@\\s]+") String email,
            @Pattern(regexp = "[0-9]{6}") String code) {
    }

    public record RefreshRequest(String refreshToken) {
    }

    public record GoogleSignInRequest(@jakarta.validation.constraints.NotBlank String idToken) {
    }

    /** {@code displayName} is optional — falls back to a generic "Player" name. */
    public record GuestSignInRequest(
            @jakarta.validation.constraints.NotBlank String deviceId,
            @Size(max = 24) String displayName) {
    }

    public record ProfileUpdateRequest(
            @Size(min = 3, max = 24) @Pattern(regexp = "[a-zA-Z0-9_]*") String username,
            String avatarEmoji) {
    }

    public record UserView(UUID id, String displayName, String username, String phone, String email, String avatarUrl, boolean isGuest) {
    }

    public record StatsView(int gamesPlayed, int wins, int traitorGames, int traitorWins) {
        public double winRate() {
            return gamesPlayed == 0 ? 0 : (double) wins / gamesPlayed;
        }
    }

    public record TokenResponse(
            String accessToken,
            String refreshToken,
            long expiresInSeconds,
            UserView user,
            // true only on the verify call that actually created the account — lets the
            // client offer the "pick a username" step once, right after signup.
            boolean newAccount) {
    }
}
