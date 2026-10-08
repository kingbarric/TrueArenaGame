package app.truearena.api.socialhuud;

import jakarta.validation.constraints.*;
import java.time.Instant;
import java.util.*;
import app.truearena.api.room.RoomDtos.RoomView;

public final class SocialHuudDtos {
    private SocialHuudDtos() {}
    public record Create(@Size(max=80) String name, String privacy, @Size(max=280) String description,
                         String gameType, Map<String,Object> gameConfig) {}
    public record Settings(@NotBlank @Size(max=80) String name, @NotBlank String privacy,
                           @Size(max=280) String description) {}
    public record Game(@NotBlank String gameType, Map<String,Object> gameConfig, @NotNull Integer activityVersion) {
        public Game(String type,Map<String,Object> config) { this(type,config,null); }
    }
    public record GameAction(@NotNull Integer activityVersion) {}
    public record Decision(boolean accepted) {}
    public record Selection(boolean selected, @NotNull Integer activityVersion) {}
    public record Code(@NotBlank @Size(min=6,max=6) String code) {}
    public record Message(@NotBlank @Size(max=1000) String text) {}
    public record Report(@NotNull UUID userId, @NotBlank @Size(max=1000) String reason, UUID messageId) {}
    public record Person(UUID userId, String username, String displayName, String avatarUrl,
                         String status, Instant joinedAt) {}
    public record ChatMessage(UUID id, UUID userId, String username, String avatarUrl, String text, Instant at) {}
    public record Capacity(int min, int max, List<Integer> allowed) {}
    public record GameOption(String gameType, Capacity capacity) {}
    public record View(UUID id, String code, UUID ownerId, String name, String description, String privacy,
                       String status, String activity, String gameType, int activityVersion, UUID currentRoomId,
                       int participantCount, int viewerCount, int playerCount, boolean participant,
                       String joinRequestStatus, String gameRequestStatus, Capacity capacity,
                       List<Person> participants, List<Person> joinRequests, List<Person> gameRequests,
                       List<UUID> selectedPlayers, Instant createdAt) {}
    public record Match(View huud, RoomView room) {}
}
