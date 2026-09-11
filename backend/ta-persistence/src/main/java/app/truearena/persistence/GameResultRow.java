package app.truearena.persistence;

import io.r2dbc.postgresql.codec.Json;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

@Table("game_results")
public record GameResultRow(
        @Id UUID id,
        @Column("game_session_id") UUID gameSessionId,
        @Column("winning_side") String winningSide,
        @Column("per_player_outcome") Json perPlayerOutcome,
        @Column("created_at") Instant createdAt
) {
    public static GameResultRow of(UUID gameSessionId, String winningSide, String perPlayerOutcomeJson) {
        return new GameResultRow(null, gameSessionId, winningSide, Json.of(perPlayerOutcomeJson), null);
    }
}
