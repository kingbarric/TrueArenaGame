package app.truearena.api.room;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class RoomDtos {

    private RoomDtos() {
    }

    /** groupId is optional — null creates an ad-hoc / web-funnel room. */
    public record CreateRoomRequest(UUID groupId) {
    }

    public record JoinRoomRequest(
            @NotBlank @Size(min = 6, max = 6) String code,
            @Size(max = 24) String nickname) {
    }

    public record RoomMemberView(UUID userId, String nickname, String connectionStatus, boolean ready) {
    }

    public record RoomView(
            UUID id,
            String code,
            UUID groupId,
            UUID hostId,
            String status,
            Instant createdAt,
            List<RoomMemberView> members,
            String wsUrl,
            String sessionToken) {
    }
}
