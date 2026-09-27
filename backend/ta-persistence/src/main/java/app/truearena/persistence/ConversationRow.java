package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * A DM (ordered pair, same convention as {@link FriendRow} — see
 * {@link FriendRow#lowerOf} for why it's string order, not
 * {@code UUID#compareTo}) or a group chat (one conversation per
 * {@code groups} row). Exactly one of {@code (dmLowUserId, dmHighUserId)} /
 * {@code groupId} is set, enforced by a DB CHECK.
 */
@Table("conversations")
public record ConversationRow(
        @Id UUID id,
        String type,
        @Column("dm_low_user_id") UUID dmLowUserId,
        @Column("dm_high_user_id") UUID dmHighUserId,
        @Column("group_id") UUID groupId,
        @Column("created_at") Instant createdAt
) {
    public static final String DM = "dm";
    public static final String GROUP = "group";

    public static ConversationRow dm(UUID userA, UUID userB) {
        UUID low = FriendRow.lowerOf(userA, userB);
        UUID high = low.equals(userA) ? userB : userA;
        return new ConversationRow(null, DM, low, high, null, null);
    }

    public static ConversationRow group(UUID groupId) {
        return new ConversationRow(null, GROUP, null, null, groupId, null);
    }

    /** The other participant in a DM, given one side of it — meaningless for a group conversation. */
    public UUID otherDmUser(UUID selfId) {
        return dmLowUserId.equals(selfId) ? dmHighUserId : dmLowUserId;
    }
}
