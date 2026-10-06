package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("rooms")
public record RoomRow(
        @Id UUID id,
        String code,
        @Column("group_id") UUID groupId,
        @Column("host_id") UUID hostId,
        String status,
        @Column("game_type") String gameType,
        @Column("stake_coins") long stakeCoins,
        /** Host-chosen game options as JSON; null means the game's defaults. */
        @Column("game_config") String gameConfig,
        /**
         * The host's request for a rated match. Only a request: the server
         * decides a finished game's actual rated-ness (see
         * {@code RatedMatchPolicy}), so a "ranked" room that turns out to hold
         * a Cyber Agent is still recorded unranked.
         */
        boolean ranked,
        @Column("created_at") Instant createdAt
) {
    public static RoomRow create(String code, UUID groupId, UUID hostId, String gameType, long stakeCoins,
                                 String gameConfig, boolean ranked) {
        return new RoomRow(null, code, groupId, hostId, "lobby", gameType, stakeCoins, gameConfig, ranked, null);
    }

    public RoomRow withHost(UUID newHostId) {
        return new RoomRow(id, code, groupId, newHostId, status, gameType, stakeCoins, gameConfig, ranked, createdAt);
    }

    public RoomRow withStatus(String newStatus) {
        return new RoomRow(id, code, groupId, hostId, newStatus, gameType, stakeCoins, gameConfig, ranked, createdAt);
    }
}
