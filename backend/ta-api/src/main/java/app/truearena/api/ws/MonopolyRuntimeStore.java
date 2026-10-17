package app.truearena.api.ws;

import app.truearena.game.monopoly.MonopolyState;
import app.truearena.room.RoomRuntime;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.UUID;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/** Server-private recovery; never return this data through room/game snapshots. */
@Component
public class MonopolyRuntimeStore {
    public record Saved(MonopolyState.Checkpoint state, boolean paused, long remainingMs) {}
    public record Recovery(UUID sessionId, Saved saved) {}
    private final DatabaseClient db;
    private final ObjectMapper mapper;

    public MonopolyRuntimeStore(DatabaseClient db, ObjectMapper mapper) {
        this.db = db;
        this.mapper = mapper.copy().disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
    }

    public Mono<Void> save(RoomRuntime rt) {
        if (!(rt.state() instanceof MonopolyState state)) return Mono.empty();
        long remaining = rt.paused ? rt.timerRemainingMs
                : Math.max(0, rt.timerDeadlineMs - System.currentTimeMillis());
        return Mono.fromCallable(() -> mapper.writeValueAsString(new Saved(state.checkpoint(), rt.paused, remaining)))
                .flatMap(json -> db.sql("UPDATE game_sessions SET runtime_state=CAST(:state AS jsonb), phase=:phase, round=:round "
                                + "WHERE id=:id AND ended_at IS NULL")
                        .bind("state", json).bind("phase", state.phase()).bind("round", state.round())
                        .bind("id", rt.gameSessionId).fetch().rowsUpdated())
                .flatMap(count -> count == 1 ? Mono.<Void>empty()
                        : Mono.error(new IllegalStateException("Monopoly session checkpoint was not saved")));
    }

    public Mono<Recovery> load(UUID room) {
        return db.sql("SELECT id,runtime_state::text AS saved FROM game_sessions "
                        + "WHERE room_id=:room AND game_type='monopoly' AND ended_at IS NULL "
                        + "AND runtime_state IS NOT NULL ORDER BY started_at DESC LIMIT 1")
                .bind("room", room)
                .map((row, metadata) -> new String[]{row.get("id", UUID.class).toString(), row.get("saved", String.class)})
                .one().flatMap(row -> Mono.fromCallable(() -> new Recovery(UUID.fromString(row[0]),
                        mapper.readValue(row[1], Saved.class))));
    }

    /** Only an in_game room with no runtime/checkpoint reaches this legacy repair. */
    public Mono<Void> returnInterruptedToSetup(UUID room) {
        return db.sql("UPDATE game_sessions SET phase='Interrupted',ended_at=now() "
                        + "WHERE room_id=:room AND ended_at IS NULL AND runtime_state IS NULL")
                .bind("room", room).fetch().rowsUpdated()
                .then(db.sql("UPDATE rooms SET status='lobby' WHERE id=:room AND game_type='monopoly' AND status='in_game'")
                        .bind("room", room).fetch().rowsUpdated()).then();
    }
}
