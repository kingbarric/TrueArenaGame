package app.truearena.api.huud;

import app.truearena.api.huud.HuudDtos.FeedItem;
import app.truearena.api.huud.HuudDtos.PersonView;
import app.truearena.api.huudspace.HuudSpaceService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.UserRepository;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

/**
 * Plain text posts on the feed. They go to your friends only — the Friends
 * tab, never strangers' For you — so a young player's words stay among
 * people they know. Five posts in ten minutes is the limit; blocked people
 * never see each other's posts.
 */
@Service
public class FeedPostService {

    static final int BURST = 5;

    private final DatabaseClient db;
    private final UserRepository users;

    public FeedPostService(DatabaseClient db, UserRepository users) {
        this.db = db;
        this.users = users;
    }

    public Mono<FeedItem> post(UUID author, String body) {
        String text = body == null ? "" : body.strip();
        if (text.isEmpty()) return Mono.error(ApiExceptions.badRequest("Write something first"));
        if (text.length() > 280) return Mono.error(ApiExceptions.badRequest("Keep it under 280 letters"));
        return users.findById(author)
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("unknown user")))
                .flatMap(me -> me.isGuest()
                        ? Mono.error(ApiExceptions.forbidden("Verify your phone or email to post"))
                        : db.sql("SELECT count(*) AS n FROM feed_posts WHERE author_id=:me AND created_at > now() - interval '10 minutes'")
                                .bind("me", author).map((r, m) -> ((Number) r.get("n")).intValue()).one()
                                .flatMap(recent -> recent >= BURST
                                        ? Mono.error(ApiExceptions.conflict("That's a lot of posts — try again in a little while"))
                                        : db.sql("INSERT INTO feed_posts(author_id,body) VALUES(:me,:body) RETURNING id, created_at")
                                                .bind("me", author).bind("body", text)
                                                .map((r, m) -> new FeedItem("post", "text:" + r.get("id", UUID.class),
                                                        r.get("created_at", java.time.OffsetDateTime.class).toInstant(),
                                                        new PersonView(author, me.displayName(), me.username(), me.avatarUrl(), false),
                                                        null, text, null, null, null, null))
                                                .one()));
    }

    public Mono<Void> delete(UUID author, UUID id) {
        return db.sql("UPDATE feed_posts SET deleted_at=now() WHERE id=:id AND author_id=:me AND deleted_at IS NULL")
                .bind("id", id).bind("me", author).fetch().rowsUpdated()
                .flatMap(n -> n == 0 ? Mono.error(ApiExceptions.notFound("No post of yours to delete")) : Mono.<Void>empty());
    }

    /** ❤️ 👍 😂 😮 🔥 👏 — the same emoji again takes it back. */
    static final java.util.List<String> EMOJI = java.util.List.of("❤️", "👍", "😂", "😮", "🔥", "👏");

    /**
     * React to a post you can see (yours or a friend's). One reaction each:
     * a different emoji replaces yours, the same one removes it.
     */
    public Mono<HuudDtos.Reactions> react(UUID user, UUID postId, String emoji) {
        if (emoji == null || !EMOJI.contains(emoji)) return Mono.error(ApiExceptions.badRequest("Pick one of the reactions"));
        return db.sql("SELECT EXISTS(SELECT 1 FROM feed_posts p WHERE p.id=:post AND p.deleted_at IS NULL "
                        + "AND (p.author_id=:uid OR EXISTS(SELECT 1 FROM friends f WHERE f.status='accepted' "
                        + "AND f.low_user_id=LEAST(:uid,p.author_id) AND f.high_user_id=GREATEST(:uid,p.author_id))) "
                        + "AND NOT " + HuudSpaceService.blockedSql("p.author_id", ":uid") + ") AS ok")
                .bind("post", postId).bind("uid", user).map((r, m) -> Boolean.TRUE.equals(r.get("ok", Boolean.class))).one()
                .flatMap(ok -> !ok ? Mono.error(ApiExceptions.notFound("That post isn't here any more"))
                        : db.sql("SELECT emoji FROM feed_post_reactions WHERE post_id=:post AND user_id=:uid")
                                .bind("post", postId).bind("uid", user).map((r, m) -> r.get("emoji", String.class)).one()
                                .map(java.util.Optional::of).defaultIfEmpty(java.util.Optional.empty())
                                .flatMap(current -> current.filter(emoji::equals).isPresent()
                                        ? db.sql("DELETE FROM feed_post_reactions WHERE post_id=:post AND user_id=:uid")
                                                .bind("post", postId).bind("uid", user).fetch().rowsUpdated()
                                        : db.sql("INSERT INTO feed_post_reactions(post_id,user_id,emoji) VALUES(:post,:uid,:emoji) "
                                                        + "ON CONFLICT(post_id,user_id) DO UPDATE SET emoji=EXCLUDED.emoji, created_at=now()")
                                                .bind("post", postId).bind("uid", user).bind("emoji", emoji).fetch().rowsUpdated()))
                .then(reactions(postId, user));
    }

    Mono<HuudDtos.Reactions> reactions(UUID postId, UUID viewer) {
        return db.sql("SELECT emoji, count(*) AS n, bool_or(user_id=:uid) AS mine FROM feed_post_reactions "
                        + "WHERE post_id=:post GROUP BY emoji")
                .bind("post", postId).bind("uid", viewer)
                .map((r, m) -> new Object[]{r.get("emoji", String.class), ((Number) r.get("n")).intValue(),
                        Boolean.TRUE.equals(r.get("mine", Boolean.class))})
                .all().collectList()
                .map(rows -> {
                    var counts = new java.util.LinkedHashMap<String, Integer>();
                    String mine = null;
                    int total = 0;
                    for (String e : EMOJI) {
                        for (Object[] row : rows) {
                            if (e.equals(row[0])) {
                                counts.put(e, (int) row[1]);
                                total += (int) row[1];
                                if ((boolean) row[2]) mine = e;
                            }
                        }
                    }
                    return new HuudDtos.Reactions(total, counts, mine);
                });
    }

    /** The Friends tab: your posts and your friends'. */
    Flux<FeedItem> friendsPosts(UUID viewer, int limit) {
        return db.sql("SELECT p.id, p.body, p.created_at, u.id AS user_id, u.display_name, u.username, u.avatar_url, "
                        + "(u.id <> :uid) AS friend FROM feed_posts p JOIN users u ON u.id=p.author_id "
                        + "WHERE p.deleted_at IS NULL AND (p.author_id=:uid OR EXISTS(SELECT 1 FROM friends f WHERE f.status='accepted' "
                        + "AND f.low_user_id=LEAST(:uid,p.author_id) AND f.high_user_id=GREATEST(:uid,p.author_id))) "
                        + "AND NOT " + HuudSpaceService.blockedSql("p.author_id", ":uid") + " "
                        + "ORDER BY p.created_at DESC LIMIT " + limit)
                .bind("uid", viewer)
                .map((r, m) -> new FeedItem("post", "text:" + r.get("id", UUID.class),
                        r.get("created_at", java.time.OffsetDateTime.class).toInstant(),
                        new PersonView(r.get("user_id", UUID.class), r.get("display_name", String.class),
                                r.get("username", String.class), r.get("avatar_url", String.class),
                                Boolean.TRUE.equals(r.get("friend", Boolean.class))),
                        null, r.get("body", String.class), null, null, null, null))
                .all()
                .concatMap(item -> reactions(UUID.fromString(item.id().substring("text:".length())), viewer)
                        .map(reactions -> new FeedItem(item.kind(), item.id(), item.at(), item.actor(), item.gameType(),
                                item.message(), null, null, null, null, reactions)));
    }

}
