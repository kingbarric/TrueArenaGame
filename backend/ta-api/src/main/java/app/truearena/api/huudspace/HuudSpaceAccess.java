package app.truearena.api.huudspace;

import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.util.UUID;

/**
 * Who may be in a Huud's voice room ({@code huud-<id>}): the people in it —
 * listening, unless they're the host or were handed the mic.
 * Kept apart from {@link HuudSpaceService} so the call code can ask without
 * depending on rooms and games.
 */
@Component
public class HuudSpaceAccess {
    public static final String VOICE_PREFIX = "huud-";

    private final DatabaseClient db;

    public HuudSpaceAccess(DatabaseClient db) {
        this.db = db;
    }

    /** The host, or someone the host handed the mic. Everyone else in the Huud listens. */
    public Mono<Boolean> canSpeak(UUID user, String roomName) {
        UUID id;
        try {
            id = UUID.fromString(roomName.substring(VOICE_PREFIX.length()));
        } catch (IllegalArgumentException | IndexOutOfBoundsException e) {
            return Mono.just(false);
        }
        return db.sql("SELECT EXISTS(SELECT 1 FROM huud_space_members m JOIN huud_spaces s ON s.id=m.huud_space_id "
                        + "WHERE s.id=:id AND s.status='active' AND m.user_id=:user AND m.left_at IS NULL AND NOT m.removed "
                        + "AND (s.owner_id=:user OR m.can_speak)) AS ok")
                .bind("id", id).bind("user", user)
                .map((r, m) -> Boolean.TRUE.equals(r.get("ok", Boolean.class))).one();
    }

    public Mono<Boolean> canTalk(UUID user, String roomName) {
        UUID id;
        try {
            id = UUID.fromString(roomName.substring(VOICE_PREFIX.length()));
        } catch (IllegalArgumentException | IndexOutOfBoundsException e) {
            return Mono.just(false);
        }
        return db.sql("SELECT EXISTS(SELECT 1 FROM huud_space_members m JOIN huud_spaces s ON s.id=m.huud_space_id "
                        + "WHERE s.id=:id AND s.status='active' AND m.user_id=:user AND m.left_at IS NULL AND NOT m.removed) AS ok")
                .bind("id", id).bind("user", user)
                .map((r, m) -> Boolean.TRUE.equals(r.get("ok", Boolean.class))).one();
    }
}
