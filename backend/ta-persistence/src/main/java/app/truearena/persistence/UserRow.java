package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("users")
public record UserRow(
        @Id UUID id,
        @Column("display_name") String displayName,
        @Column("avatar_url") String avatarUrl,
        String phone,
        String email,
        String username,
        @Column("is_guest") boolean isGuest,
        @Column("device_id") String deviceId,
        @Column("is_bot") boolean isBot,
        /** Legacy saved-agent owner. System-pool agents leave this null. */
        @Column("owner_user_id") UUID ownerUserId,
        /** Legacy game assignment, or "system_pool" for reusable identities. */
        @Column("bot_game_type") String botGameType,
        /** Legacy default. Active pool-agent difficulty lives on room_members. */
        @Column("bot_difficulty") String botDifficulty,
        @Column("public_key") String publicKey,
        @Column("created_at") Instant createdAt
) {
    public static UserRow newUser(String phone, String email, String displayName, String username) {
        return new UserRow(null, displayName, null, phone, email, username, false, null, false, null, null, null, null, null);
    }

    public static UserRow newGuest(String deviceId, String displayName, String username) {
        return new UserRow(null, displayName, null, null, null, username, true, deviceId, false, null, null, null, null, null);
    }

    /** Legacy constructor retained for old saved-agent rows and pool test fixtures. */
    public static UserRow newBot(String displayName, String username, UUID ownerUserId,
                                 String gameType, String difficulty) {
        return new UserRow(null, displayName, null, null, null, username, false, null, true,
                ownerUserId, gameType, difficulty, null, null);
    }

    /** Legacy saved-agent helper retained while old rows remain readable. */
    public UserRow renamed(String newDisplayName) {
        return new UserRow(id, newDisplayName, avatarUrl, phone, email, username, isGuest, deviceId, isBot,
                ownerUserId, botGameType, botDifficulty, publicKey, createdAt);
    }

    public UserRow withProfile(String newUsername, String newAvatarUrl) {
        return new UserRow(id, displayName,
                newAvatarUrl != null ? newAvatarUrl : avatarUrl,
                phone, email,
                newUsername != null ? newUsername : username,
                isGuest, deviceId, isBot, ownerUserId, botGameType, botDifficulty, publicKey, createdAt);
    }

    /** Attaches a verified phone/email to a guest row in place — same id, same
     * room membership and stats, just no longer a guest. Exactly one of
     * {@code newPhone}/{@code newEmail} is non-null (see AuthController). */
    public UserRow upgraded(String newPhone, String newEmail) {
        return new UserRow(id, displayName, avatarUrl,
                newPhone != null ? newPhone : phone,
                newEmail != null ? newEmail : email,
                username, false, deviceId, isBot, ownerUserId, botGameType, botDifficulty, publicKey, createdAt);
    }

    /** Uploads this device's E2E public key — see `POST /me/public-key`. */
    public UserRow withPublicKey(String newPublicKey) {
        return new UserRow(id, displayName, avatarUrl, phone, email, username, isGuest, deviceId, isBot,
                ownerUserId, botGameType, botDifficulty, newPublicKey, createdAt);
    }
}
