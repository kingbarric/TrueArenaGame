package app.truearena.api.admin;

import app.truearena.api.support.ApiExceptions;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Player reports for the team, behind the admin key (see {@link AdminKeyFilter}).
 * Read by /notvisible/reports: what was reported, by whom, about whom, with the
 * exact message or post, and how many times that player has been reported.
 */
@RestController
@RequestMapping("/api/v1/admin/reports")
@Tag(name = "Admin", description = "Internal tooling")
public class AdminReportsController {

    public record Who(UUID id, String displayName, String username) {
    }

    public record ReportView(UUID id, Instant createdAt, String reason, String details, Who reporter, Who reported,
                             int reportsAgainst, UUID huudSpaceId, String huudName, String messageBody,
                             UUID postId, String postBody, boolean postRemoved, String status,
                             Instant reviewedAt, String reviewedBy, String reviewNote) {
    }

    public record ReviewRequest(String note, String by, Boolean removePost) {
    }

    private final DatabaseClient db;

    public AdminReportsController(DatabaseClient db) {
        this.db = db;
    }

    @GetMapping
    @Operation(summary = "Reports, newest first; status=open (default), reviewed or all")
    public Flux<ReportView> list(@RequestParam(defaultValue = "open") String status,
                                 @RequestParam(defaultValue = "100") int limit) {
        String where = switch (status) {
            case "reviewed" -> "WHERE r.status='reviewed'";
            case "all" -> "";
            default -> "WHERE r.status='open'";
        };
        return db.sql("SELECT r.*, a.display_name AS a_name, a.username AS a_user, b.display_name AS b_name, b.username AS b_user, "
                        + "(SELECT count(*) FROM player_reports x WHERE x.reported_id=r.reported_id) AS against, "
                        + "s.name AS huud_name, (p.deleted_at IS NOT NULL) AS post_removed "
                        + "FROM player_reports r JOIN users a ON a.id=r.reporter_id JOIN users b ON b.id=r.reported_id "
                        + "LEFT JOIN huud_spaces s ON s.id=r.huud_space_id LEFT JOIN feed_posts p ON p.id=r.feed_post_id "
                        + where + " ORDER BY r.created_at DESC LIMIT " + Math.max(1, Math.min(limit, 500)))
                .map((row, m) -> new ReportView(row.get("id", UUID.class), at(row.get("created_at")),
                        row.get("reason", String.class), row.get("details", String.class),
                        new Who(row.get("reporter_id", UUID.class), row.get("a_name", String.class), row.get("a_user", String.class)),
                        new Who(row.get("reported_id", UUID.class), row.get("b_name", String.class), row.get("b_user", String.class)),
                        ((Number) row.get("against")).intValue(), row.get("huud_space_id", UUID.class),
                        row.get("huud_name", String.class), row.get("message_body", String.class),
                        row.get("feed_post_id", UUID.class), row.get("post_body", String.class),
                        Boolean.TRUE.equals(row.get("post_removed", Boolean.class)), row.get("status", String.class),
                        at(row.get("reviewed_at")), row.get("reviewed_by", String.class), row.get("review_note", String.class)))
                .all();
    }

    @PostMapping("/{id}/review")
    @Operation(summary = "Mark a report reviewed, with an optional note; removePost takes a reported post down")
    public Mono<Void> review(@PathVariable UUID id, @RequestBody ReviewRequest body) {
        String note = body.note() == null || body.note().isBlank() ? null : body.note().strip();
        if (note != null && note.length() > 500) return Mono.error(ApiExceptions.badRequest("note is too long"));
        var sql = db.sql("UPDATE player_reports SET status='reviewed', reviewed_at=now(), reviewed_by=:by, review_note=:note "
                        + "WHERE id=:id RETURNING feed_post_id")
                .bind("id", id);
        sql = body.by() == null || body.by().isBlank() ? sql.bindNull("by", String.class) : sql.bind("by", body.by().strip());
        sql = note == null ? sql.bindNull("note", String.class) : sql.bind("note", note);
        return sql.map((r, m) -> java.util.Optional.ofNullable(r.get("feed_post_id", UUID.class))).one()
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such report")))
                .flatMap(post -> Boolean.TRUE.equals(body.removePost()) && post.isPresent()
                        ? db.sql("UPDATE feed_posts SET deleted_at=COALESCE(deleted_at, now()) WHERE id=:post")
                                .bind("post", post.get()).fetch().rowsUpdated().then()
                        : Mono.<Void>empty());
    }

    private static Instant at(Object value) {
        if (value == null) return null;
        if (value instanceof Instant i) return i;
        return ((OffsetDateTime) value).toInstant();
    }
}
