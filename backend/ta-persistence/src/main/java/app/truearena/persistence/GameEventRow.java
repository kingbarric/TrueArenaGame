package app.truearena.persistence;

import io.r2dbc.postgresql.codec.Json;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("game_events")
public record GameEventRow(
        @Id UUID id,
        @Column("game_session_id") UUID gameSessionId,
        long seq,
        String type,
        Json payload,
        @Column("visibility_scope") String visibilityScope,
        @Column("visibility_key") String visibilityKey,
        @Column("created_at") Instant createdAt
) {
    public static GameEventRow of(UUID gameSessionId, long seq, String type, String payloadJson,
                                  String visibilityScope, String visibilityKey) {
        return new GameEventRow(null, gameSessionId, seq, type, Json.of(payloadJson), visibilityScope, visibilityKey, null);
    }
}
