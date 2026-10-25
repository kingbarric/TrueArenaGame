package app.truearena.api.room;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class RoomDtos {

    private RoomDtos() {
    }

    /**
     * groupId is optional — null creates an ad-hoc / web-funnel room. gameType is
     * optional too — null/blank defaults to {@code "truearena"}; the only other
     * value today is {@code "wordbluff"} (see {@code GameOrchestrator}).
     * The legacy stake field is accepted only when absent or zero; any nonzero
     * value is rejected before creating or reusing a room.
     */
    public record CreateRoomRequest(UUID groupId, String gameType, Long stake,
                                    java.util.Map<String, Object> gameConfig,
                                    /** Optional; omitted = casual. A request, not a guarantee — see RatedMatchPolicy. */
                                    Boolean ranked) {
    }

    public record JoinRoomRequest(
            @NotBlank @Size(min = 6, max = 6) String code,
            @Size(max = 24) String nickname) {
    }

    public record WatchRoomRequest(
            @NotBlank @Size(min = 6, max = 6) String code) {
    }

    public record RoomMemberView(UUID userId, String nickname, String connectionStatus, boolean ready,
                                 boolean isBot, String avatarUrl) {
    }

    /** One row in the spectator-discovery list — a friend's room that's actually started, not just created. */
    public record DiscoverableRoomView(UUID roomId, String code, String gameType, String hostName, int connectedCount) {
    }

    public record RoomView(
            UUID id,
            String code,
            UUID groupId,
            UUID hostId,
            String status,
            String gameType,
            long stakeCoins,
            Instant createdAt,
            List<RoomMemberView> members,
            String wsUrl,
            String sessionToken,
            /** The host asked for a rated match — the final say is RatedMatchPolicy's, at game end. */
            boolean ranked) {
    }
}
