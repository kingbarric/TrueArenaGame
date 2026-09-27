package app.truearena.api.group;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.UUID;

public final class GroupDtos {

    private GroupDtos() {
    }

    /** avatarEmoji is optional — one of the client's avatar presets, or null for the initial-letter fallback. */
    public record CreateGroupRequest(@NotBlank @Size(max = 60) String name, @Size(max = 8) String avatarEmoji) {
    }

    public record AddMemberRequest(@NotNull UUID userId) {
    }

    public record GroupView(UUID id, String name, String avatarEmoji, UUID createdBy, Instant createdAt) {
    }

    public record GroupMemberView(UUID userId, String role, Instant joinedAt) {
    }
}
