package app.truearena.api.safety;

import app.truearena.api.huudspace.HuudSpaceService;
import app.truearena.api.support.ApiExceptions;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.util.Set;
import java.util.UUID;

/**
 * Block and report. Blocking keeps someone out of your Huuds (and you out of
 * theirs), hides their chat and their Huuds from you, and ends any friendship
 * or friend request between you. A report is kept for the PlayHuud team with
 * whatever message it was about.
 */
@Service
public class SafetyService {

    static final Set<String> REASONS = Set.of("mean", "unsafe", "spam", "other");

    public record BlockedPlayer(UUID userId, String displayName, String username, String avatarUrl, Instant at) {
    }

    private final DatabaseClient db;
    private final HuudSpaceService huuds;

    public SafetyService(DatabaseClient db, HuudSpaceService huuds) {
        this.db = db;
        this.huuds = huuds;
    }

    public Mono<Void> block(UUID me, UUID them) {
        if (me.equals(them)) return Mono.error(ApiExceptions.badRequest("You can't block yourself"));
        return db.sql("INSERT INTO player_blocks(blocker_id,blocked_id) VALUES(:me,:them) ON CONFLICT DO NOTHING")
                .bind("me", me).bind("them", them).fetch().rowsUpdated()
                .then(db.sql("DELETE FROM friends WHERE low_user_id=LEAST(:me,:them) AND high_user_id=GREATEST(:me,:them)")
                        .bind("me", me).bind("them", them).fetch().rowsUpdated())
                // Out of the Huud you're hosting, if they're in it.
                .then(db.sql("SELECT s.id FROM huud_spaces s JOIN huud_space_members m ON m.huud_space_id=s.id "
                                + "WHERE s.owner_id=:me AND s.status='active' AND m.user_id=:them AND m.left_at IS NULL")
                        .bind("me", me).bind("them", them).map((r, m) -> r.get("id", UUID.class)).one()
                        .flatMap(huud -> huuds.remove(me, huud, them).onErrorResume(e -> Mono.empty())))
                .then();
    }

    public Mono<Void> unblock(UUID me, UUID them) {
        return db.sql("DELETE FROM player_blocks WHERE blocker_id=:me AND blocked_id=:them")
                .bind("me", me).bind("them", them).fetch().rowsUpdated().then();
    }

    public Flux<BlockedPlayer> blocked(UUID me) {
        return db.sql("SELECT u.id, u.display_name, u.username, u.avatar_url, b.created_at FROM player_blocks b "
                        + "JOIN users u ON u.id=b.blocked_id WHERE b.blocker_id=:me ORDER BY b.created_at DESC")
                .bind("me", me)
                .map((r, m) -> new BlockedPlayer(r.get("id", UUID.class), r.get("display_name", String.class),
                        r.get("username", String.class), r.get("avatar_url", String.class),
                        r.get("created_at", java.time.OffsetDateTime.class).toInstant()))
                .all();
    }

    /** Report someone; with {@code alsoBlock} they're blocked in the same tap. */
    public Mono<Void> report(UUID me, UUID them, String reason, String details, UUID huudSpaceId, Long messageId,
                             boolean alsoBlock) {
        return report(me, them, reason, details, huudSpaceId, messageId, null, alsoBlock);
    }

    public Mono<Void> report(UUID me, UUID them, String reason, String details, UUID huudSpaceId, Long messageId,
                             UUID feedPostId, boolean alsoBlock) {
        if (me.equals(them)) return Mono.error(ApiExceptions.badRequest("You can't report yourself"));
        if (reason == null || !REASONS.contains(reason)) return Mono.error(ApiExceptions.badRequest("Pick a reason"));
        String note = details == null || details.isBlank() ? null : details.strip();
        if (note != null && note.length() > 300) note = note.substring(0, 300);
        var sql = db.sql("INSERT INTO player_reports(reporter_id,reported_id,reason,details,huud_space_id,message_id,message_body,"
                        + "feed_post_id,post_body) VALUES(:me,:them,:reason,:details,:huud,:message,"
                        + "(SELECT body FROM huud_space_messages WHERE id=:message AND user_id=:them),"
                        + ":post,(SELECT body FROM feed_posts WHERE id=:post AND author_id=:them))")
                .bind("me", me).bind("them", them).bind("reason", reason);
        sql = note == null ? sql.bindNull("details", String.class) : sql.bind("details", note);
        sql = huudSpaceId == null ? sql.bindNull("huud", UUID.class) : sql.bind("huud", huudSpaceId);
        sql = messageId == null ? sql.bindNull("message", Long.class) : sql.bind("message", messageId);
        sql = feedPostId == null ? sql.bindNull("post", UUID.class) : sql.bind("post", feedPostId);
        return sql.fetch().rowsUpdated().then(alsoBlock ? block(me, them) : Mono.empty());
    }
}
