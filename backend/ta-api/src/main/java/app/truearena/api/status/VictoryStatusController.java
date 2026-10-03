package app.truearena.api.status;

import app.truearena.api.support.ApiExceptions;
import app.truearena.api.support.CurrentUser;
import org.springframework.http.HttpStatus;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/statuses")
public class VictoryStatusController {
    private final DatabaseClient db;

    public VictoryStatusController(DatabaseClient db) {
        this.db = db;
    }

    public record StatusView(UUID id, UUID userId, String displayName, String username,
                             String avatarUrl, String gameType, Instant createdAt, Instant expiresAt) {}
    public record PostStatus(UUID roomId) {}

    @GetMapping
    public Flux<StatusView> list() {
        return CurrentUser.id().flatMapMany(uid -> db.sql("""
                SELECT s.id, s.user_id, u.display_name, u.username, u.avatar_url,
                       s.game_type, s.created_at, s.expires_at
                FROM victory_statuses s JOIN users u ON u.id = s.user_id
                WHERE s.expires_at > now() AND (s.user_id = :uid OR EXISTS (
                    SELECT 1 FROM friends f WHERE f.status = 'accepted'
                    AND f.low_user_id = LEAST(:uid, s.user_id)
                    AND f.high_user_id = GREATEST(:uid, s.user_id)))
                ORDER BY s.created_at DESC
                """).bind("uid", uid).map((row, meta) -> map(row)).all());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<StatusView> post(@RequestBody PostStatus request) {
        if (request == null || request.roomId() == null) {
            return Mono.error(ApiExceptions.badRequest("roomId is required"));
        }
        return CurrentUser.id().flatMap(uid -> db.sql("""
                SELECT gs.id, gs.game_type FROM game_sessions gs
                JOIN game_results gr ON gr.game_session_id = gs.id
                WHERE gs.room_id = :room AND gs.ended_at > now() - interval '24 hours'
                  AND gr.per_player_outcome ->> :player = 'won'
                ORDER BY gs.ended_at DESC LIMIT 1
                """).bind("room", request.roomId()).bind("player", uid.toString())
                .map((row, meta) -> new Win(row.get("id", UUID.class), row.get("game_type", String.class)))
                .one()
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("Only your completed victories can be posted")))
                .flatMap(win -> db.sql("""
                        INSERT INTO victory_statuses (user_id, game_session_id, game_type)
                        VALUES (:uid, :session, :game)
                        ON CONFLICT (user_id, game_session_id) DO UPDATE SET user_id = EXCLUDED.user_id
                        RETURNING id
                        """).bind("uid", uid).bind("session", win.sessionId())
                        .bind("game", win.gameType())
                        .map((row, meta) -> row.get("id", UUID.class)).one())
                .flatMap(id -> db.sql("""
                        SELECT s.id, s.user_id, u.display_name, u.username, u.avatar_url,
                               s.game_type, s.created_at, s.expires_at
                        FROM victory_statuses s JOIN users u ON u.id = s.user_id WHERE s.id = :id
                        """).bind("id", id).map((row, meta) -> map(row)).one()));
    }

    private record Win(UUID sessionId, String gameType) {}

    private static StatusView map(io.r2dbc.spi.Row row) {
        return new StatusView(row.get("id", UUID.class), row.get("user_id", UUID.class),
                row.get("display_name", String.class), row.get("username", String.class),
                row.get("avatar_url", String.class), row.get("game_type", String.class),
                row.get("created_at", Instant.class), row.get("expires_at", Instant.class));
    }
}
