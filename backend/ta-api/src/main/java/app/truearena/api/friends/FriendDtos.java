package app.truearena.api.friends;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class FriendDtos {

    private FriendDtos() {
    }

    public record SendFriendRequestBody(@NotBlank String username) {
    }

    /**
     * A friend, or the other side of a pending request — same shape either
     * way. {@code publicKey} rides along here (rather than a separate
     * lookup) since it's exactly the DTO a DM chat/call screen already
     * fetches to know who it's talking to — null until that user's device
     * has uploaded one (see {@code POST /me/public-key}).
     */
    /**
     * {@code agentGameType} is null for people and set for a Cyber Agent the
     * viewer owns — agents show up in the friends list alongside real
     * friends (they're players you can add to a room), and the client uses
     * this field to badge them and to skip the chat/call actions that only
     * make sense for a human.
     */
    public record FriendUserView(UUID userId, String displayName, String username, String avatarUrl,
                                 String publicKey, String agentGameType, String agentDifficulty) {
    }

    public record FriendRequestView(UUID id, FriendUserView from, Instant createdAt) {
    }

    public record FriendRequestsView(List<FriendRequestView> incoming, List<FriendRequestView> outgoing) {
    }

    /**
     * Phones already on the device (with the user's OS-level contacts
     * permission granted) — see {@code FriendService.matchContacts}. Client
     * sends whatever normalized candidates it can produce per contact
     * (v1 has no full E.164 library on the client, so this is a
     * best-effort digit match, not exact phone-number parsing).
     */
    public record ContactMatchRequest(@NotEmpty List<@NotBlank String> phones) {
    }

    public record ContactMatchView(
            String matchedPhone, UUID userId, String displayName, String username, String avatarUrl,
            boolean isFriend, boolean requestPending) {
    }

    /**
     * One search-as-you-type result — {@code requestPending} covers both
     * directions (we asked them, or they asked us) so the client can show
     * the right button (Add / Requested / Accept / Friends) without a
     * second round trip per row.
     */
    public record UserSearchResultView(UUID userId, String displayName, String username, String avatarUrl,
                                       boolean isFriend, boolean requestPending) {
    }
}
