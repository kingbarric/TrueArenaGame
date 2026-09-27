package app.truearena.voice;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Binds {@code truearena.livekit.*} (ta-app/application.yml) — the same
 * values TrueArena's RoundTable voice was originally provisioned for (Phase
 * 8), now also used to mint tokens for friend calls (1:1 and group — a
 * LiveKit room is multi-party by default, so both share this one path).
 */
@ConfigurationProperties(prefix = "truearena.livekit")
public record LiveKitProperties(String url, String apiKey, String apiSecret) {
}
