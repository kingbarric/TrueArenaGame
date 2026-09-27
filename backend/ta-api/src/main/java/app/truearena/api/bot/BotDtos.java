package app.truearena.api.bot;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.UUID;

public final class BotDtos {

    private BotDtos() {
    }

    /** {@code difficulty} is optional — "easy"/"medium"/"hard", case-insensitive, defaults to medium. */
    public record AddBotRequest(@NotBlank @Size(max = 24) String name, String difficulty) {
    }

    public record RenameAgentRequest(@NotBlank @Size(max = 24) String name) {
    }

    public record BotAddedView(UUID userId, String displayName, String difficulty) {
    }
}
