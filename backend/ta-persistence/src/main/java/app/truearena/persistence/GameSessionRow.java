package app.truearena.persistence;

import io.r2dbc.postgresql.codec.Json;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("game_sessions")
public record GameSessionRow(
        @Id UUID id,
        @Column("room_id") UUID roomId,
        @Column("game_type") String gameType,
        Json config,
        @Column("config_preset_id") UUID configPresetId,
        @Column("catalog_version") int catalogVersion,
        @Column("rng_seed") long rngSeed,
        String phase,
        int round,
        @Column("phase_ends_at") Instant phaseEndsAt,
        @Column("started_at") Instant startedAt,
        @Column("ended_at") Instant endedAt
) {
    public static GameSessionRow start(UUID roomId, String gameType, String configJson, int catalogVersion, long rngSeed) {
        return new GameSessionRow(null, roomId, gameType, Json.of(configJson), null, catalogVersion, rngSeed,
                "RoleReveal", 1, null, null, null);
    }
}
