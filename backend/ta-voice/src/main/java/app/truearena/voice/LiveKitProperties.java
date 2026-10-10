package app.truearena.voice;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Binds {@code truearena.livekit.*} (ta-app/application.yml) — the same
 * values TrueArena's RoundTable voice was originally provisioned for (Phase
 * 8), now also used to mint tokens for friend calls (1:1 and group — a
 * LiveKit room is multi-party by default, so both share this one path).
 *
 * <p>{@code url} is what clients dial. {@code apiUrl} is how this server reaches
 * LiveKit's room API; blank means the same as {@code url}. The test server sets it
 * to the internal address because its public {@code url} carries a {@code /test}
 * path prefix that LiveKit's server SDK drops.
 */
@ConfigurationProperties(prefix = "truearena.livekit")
public record LiveKitProperties(String url, String apiKey, String apiSecret, String apiUrl) {

    public String serverUrl() {
        return apiUrl == null || apiUrl.isBlank() ? url : apiUrl;
    }
}
