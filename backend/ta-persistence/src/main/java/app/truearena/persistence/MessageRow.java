package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("messages")
public record MessageRow(
        @Id UUID id,
        @Column("conversation_id") UUID conversationId,
        @Column("sender_id") UUID senderId,
        String kind,
        String text,
        @Column("room_id") UUID roomId,
        @Column("room_code") String roomCode,
        @Column("created_at") Instant createdAt
) {
    public static final String TEXT = "text";
    public static final String GAME_INVITE = "game_invite";

    public static MessageRow text(UUID conversationId, UUID senderId, String text) {
        return new MessageRow(null, conversationId, senderId, TEXT, text, null, null, null);
    }

    public static MessageRow gameInvite(UUID conversationId, UUID senderId, UUID roomId, String roomCode) {
        return new MessageRow(null, conversationId, senderId, GAME_INVITE, null, roomId, roomCode, null);
    }
}
