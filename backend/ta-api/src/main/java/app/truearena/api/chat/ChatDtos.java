package app.truearena.api.chat;

import app.truearena.api.friends.FriendDtos.FriendUserView;
import jakarta.validation.constraints.NotBlank;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class ChatDtos {

    private ChatDtos() {
    }

    public record SendTextRequest(@NotBlank String text) {
    }

    public record SendGameInviteRequest(UUID roomId) {
    }

    public record MessageView(
            UUID id, UUID senderId, String kind, String text,
            UUID roomId, String roomCode, String gameType, Instant createdAt) {
    }

    public record ConversationView(
            UUID id, String type,
            FriendUserView other, // dm only
            UUID groupId, String groupName, // group only
            MessageView lastMessage) {
    }

    public record MessagePage(List<MessageView> messages) {
    }
}
