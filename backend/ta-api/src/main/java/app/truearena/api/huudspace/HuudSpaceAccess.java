package app.truearena.api.huudspace;

import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

/**
 * Who may be in a Huud's voice room ({@code huud-<id>}): the people in it —
 * listening, unless they're the host or were handed the mic.
 *
 * <p>During a championship each match being played has a voice room of its
 * own, {@code huud-<id>-m-<matchId>}, so the people watching one board don't
 * hear another. The Huud's own room is the championship lobby. The same
 * people may be in either and the same mic rules apply; a match room only
 * exists while its match is being played.
 *
 * <p>Kept apart from {@link HuudSpaceService} so the call code can ask without
 * depending on rooms and games.
 */
@Component
public class HuudSpaceAccess {
    public static final String VOICE_PREFIX = "huud-";
    static final String MATCH_INFIX = "-m-";

    private final DatabaseClient db;

    public HuudSpaceAccess(DatabaseClient db) {
        this.db = db;
    }

    /** The voice room of one championship match in a Huud. */
    public static String matchVoiceRoom(UUID huudId, UUID matchId) {
        return VOICE_PREFIX + huudId + MATCH_INFIX + matchId;
    }

    /** A Huud voice room's Huud and, for a match room, its match. Null when it isn't one. */
    record VoiceRoom(UUID huudId, UUID matchId) {}

    static VoiceRoom parse(String roomName) {
        if (roomName == null || !roomName.startsWith(VOICE_PREFIX)) return null;
        String rest = roomName.substring(VOICE_PREFIX.length());
        try {
            if (rest.length() == 36) return new VoiceRoom(UUID.fromString(rest), null);
            if (rest.length() == 36 + MATCH_INFIX.length() + 36 && rest.startsWith(MATCH_INFIX, 36)) {
                return new VoiceRoom(UUID.fromString(rest.substring(0, 36)),
                        UUID.fromString(rest.substring(36 + MATCH_INFIX.length())));
            }
        } catch (IllegalArgumentException e) {
            return null;
        }
        return null;
    }

    /** The host, or someone the host handed the mic. Everyone else in the Huud listens. */
    public Mono<Boolean> canSpeak(UUID user, String roomName) {
        return allowed(user, roomName, " AND (s.owner_id=:user OR m.can_speak)");
    }

    public Mono<Boolean> canTalk(UUID user, String roomName) {
        return allowed(user, roomName, "");
    }

    private Mono<Boolean> allowed(UUID user, String roomName, String speaking) {
        VoiceRoom room = parse(roomName);
        if (room == null) return Mono.just(false);
        String match = room.matchId() == null ? "" : " AND EXISTS(SELECT 1 FROM championship_matches cm "
                + "JOIN championships c ON c.id=cm.championship_id WHERE cm.id=:match AND cm.status='active' "
                + "AND c.huud_space_id=s.id)";
        var sql = db.sql("SELECT EXISTS(SELECT 1 FROM huud_space_members m JOIN huud_spaces s ON s.id=m.huud_space_id "
                        + "WHERE s.id=:id AND s.status='active' AND s.live_since IS NOT NULL AND m.user_id=:user "
                        + "AND m.left_at IS NULL AND NOT m.removed AND m.live_at IS NOT NULL" + speaking + match + ") AS ok")
                .bind("id", room.huudId()).bind("user", user);
        if (room.matchId() != null) sql = sql.bind("match", room.matchId());
        return sql.map((r, m) -> Boolean.TRUE.equals(r.get("ok", Boolean.class))).one();
    }

    /** Every voice room of the Huud right now: its own, plus one per match being played. */
    public Flux<String> voiceRooms(UUID huudId) {
        return Flux.concat(Mono.just(VOICE_PREFIX + huudId),
                db.sql("SELECT cm.id FROM championship_matches cm JOIN championships c ON c.id=cm.championship_id "
                                + "WHERE c.huud_space_id=:id AND cm.status='active'")
                        .bind("id", huudId).map((r, m) -> matchVoiceRoom(huudId, r.get("id", UUID.class))).all());
    }
}
