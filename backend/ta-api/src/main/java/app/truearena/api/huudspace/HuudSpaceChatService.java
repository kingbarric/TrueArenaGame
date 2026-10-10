package app.truearena.api.huudspace;

import app.truearena.api.huudspace.HuudSpaceDtos.ChatMessage;
import app.truearena.api.huudspace.HuudSpaceDtos.Person;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.support.ApiExceptions;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Huud chat — the conversation that keeps going across games. Only people in
 * the Huud read or write it; messages from someone you blocked never reach
 * you; five messages in ten seconds is the limit, so nobody floods it.
 */
@Service
public class HuudSpaceChatService {

    static final int PAGE = 50;
    static final int BURST = 5;

    private final HuudSpaceService huuds;
    private final DatabaseClient db;
    private final InboxRegistry inbox;

    public HuudSpaceChatService(HuudSpaceService huuds, DatabaseClient db, InboxRegistry inbox) {
        this.huuds = huuds;
        this.db = db;
        this.inbox = inbox;
    }

    /** The latest messages, oldest first; {@code before} pages further back. */
    public Flux<ChatMessage> messages(UUID user, UUID id, Long before) {
        return huuds.requireMember(id, user).thenMany(db.sql(
                        "SELECT * FROM (SELECT c.id, c.body, c.created_at, u.id AS user_id, u.display_name, u.username, u.avatar_url "
                                + "FROM huud_space_messages c JOIN users u ON u.id=c.user_id "
                                + "WHERE c.huud_space_id=:id AND (:before = 0 OR c.id < :before) "
                                + "AND NOT EXISTS(SELECT 1 FROM player_blocks b WHERE b.blocker_id=:user AND b.blocked_id=c.user_id) "
                                + "ORDER BY c.id DESC LIMIT " + PAGE + ") recent ORDER BY id")
                .bind("id", id).bind("user", user).bind("before", before == null ? 0L : before)
                .map((r, m) -> new ChatMessage(((Number) r.get("id")).longValue(),
                        new Person(r.get("user_id", UUID.class), r.get("display_name", String.class),
                                r.get("username", String.class), r.get("avatar_url", String.class), false, true, false, null),
                        r.get("body", String.class), HuudSpaceService.instant(r.get("created_at"))))
                .all());
    }

    public Mono<ChatMessage> send(UUID user, UUID id, String body) {
        String text = body == null ? "" : body.strip();
        if (text.isEmpty()) return Mono.error(ApiExceptions.badRequest("Type something first"));
        if (text.length() > 300) return Mono.error(ApiExceptions.badRequest("That's a bit long — keep it under 300 letters"));
        return huuds.requireMember(id, user)
                .then(db.sql("SELECT count(*) AS n FROM huud_space_messages WHERE huud_space_id=:id AND user_id=:user "
                                + "AND created_at > now() - interval '10 seconds'")
                        .bind("id", id).bind("user", user).map((r, m) -> ((Number) r.get("n")).intValue()).one())
                .flatMap(recent -> recent >= BURST
                        ? Mono.error(ApiExceptions.conflict("Slow down a little 🙂"))
                        : db.sql("INSERT INTO huud_space_messages(huud_space_id,user_id,body) VALUES(:id,:user,:body) RETURNING id, created_at")
                                .bind("id", id).bind("user", user).bind("body", text)
                                .map((r, m) -> Map.entry(((Number) r.get("id")).longValue(), HuudSpaceService.instant(r.get("created_at"))))
                                .one())
                .zipWith(db.sql("SELECT display_name, username, avatar_url FROM users WHERE id=:user").bind("user", user)
                        .fetch().one())
                .map(t -> new ChatMessage(t.getT1().getKey(),
                        new Person(user, (String) t.getT2().get("display_name"), (String) t.getT2().get("username"),
                                (String) t.getT2().get("avatar_url"), false, true, false, null),
                        text, t.getT1().getValue()))
                .doOnNext(message -> deliver(id, message));
    }

    /** Straight to everyone in the Huud — except people who blocked the sender. */
    private void deliver(UUID id, ChatMessage message) {
        db.sql("SELECT m.user_id FROM huud_space_members m WHERE m.huud_space_id=:id AND m.left_at IS NULL "
                        + "AND NOT EXISTS(SELECT 1 FROM player_blocks b WHERE b.blocker_id=m.user_id AND b.blocked_id=:sender)")
                .bind("id", id).bind("sender", message.from().userId())
                .map((r, m) -> r.get("user_id", UUID.class)).all()
                .subscribe(member -> {
                    Map<String, Object> data = new HashMap<>();
                    data.put("huudSpaceId", id.toString());
                    data.put("event", "chat");
                    data.put("by", message.from().userId().toString());
                    data.put("message", message);
                    inbox.notify(member, Map.of("type", "HUUD_SPACE", "data", data));
                }, e -> { });
    }
}
