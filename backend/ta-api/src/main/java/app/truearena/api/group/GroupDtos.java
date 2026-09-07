package app.truearena.api.group;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.UUID;

public final class GroupDtos {

    private GroupDtos() {
    }

    public record CreateGroupRequest(@NotBlank @Size(max = 60) String name) {
    }

    public record AddMemberRequest(@NotNull UUID userId) {
    }

    public record GroupView(UUID id, String name, UUID createdBy, Instant createdAt) {
    }

    public record GroupMemberView(UUID userId, String role, Instant joinedAt) {
    }
}
