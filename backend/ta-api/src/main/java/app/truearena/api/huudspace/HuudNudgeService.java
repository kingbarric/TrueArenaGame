package app.truearena.api.huudspace;

import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.push.PushNotificationService;
import app.truearena.api.support.ApiExceptions;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

@Service
public class HuudNudgeService {
    private final DatabaseClient db;
    private final InboxRegistry inbox;
    private final PushNotificationService push;
    public HuudNudgeService(DatabaseClient db, InboxRegistry inbox, PushNotificationService push) {
        this.db=db; this.inbox=inbox; this.push=push;
    }
    public Mono<Void> nudge(UUID sender, UUID huud, UUID target) {
        if (sender.equals(target)) return Mono.error(ApiExceptions.badRequest("You cannot nudge yourself"));
        return db.sql("""
                SELECT s.name, u.username FROM huud_spaces s
                JOIN huud_space_members mine ON mine.huud_space_id=s.id AND mine.user_id=:sender
                JOIN huud_space_members recipient ON recipient.huud_space_id=s.id AND recipient.user_id=:target
                JOIN users u ON u.id=:sender
                WHERE s.id=:huud AND s.status='active' AND s.live_since IS NOT NULL
                AND mine.left_at IS NULL AND NOT mine.removed AND mine.live_at IS NOT NULL
                AND mine.last_seen_at > now()-interval '75 seconds'
                AND recipient.left_at IS NULL AND NOT recipient.removed AND NOT recipient.muted
                AND (recipient.live_at IS NULL OR recipient.last_seen_at <= now()-interval '75 seconds' OR :background)
                AND NOT EXISTS(SELECT 1 FROM player_blocks b WHERE
                    (b.blocker_id=:sender AND b.blocked_id=:target) OR (b.blocker_id=:target AND b.blocked_id=:sender))
                """)
                .bind("sender",sender).bind("target",target).bind("huud",huud)
                .bind("background",inbox.isBackgrounded(target))
                .map((r,m)->Map.entry(r.get("name",String.class),r.get("username",String.class)))
                .one().switchIfEmpty(Mono.error(ApiExceptions.conflict("This member cannot be nudged right now")))
                .flatMap(names -> db.sql("""
                    INSERT INTO huud_member_nudges(huud_space_id,target_user_id,sent_by) VALUES(:huud,:target,:sender)
                    ON CONFLICT(huud_space_id,target_user_id) DO UPDATE SET sent_by=EXCLUDED.sent_by,sent_at=now()
                    WHERE huud_member_nudges.sent_at <= now()-interval '5 minutes'
                    RETURNING sent_by
                    """)
                    .bind("huud",huud).bind("target",target).bind("sender",sender)
                    .map((r,m)->r.get("sent_by",UUID.class)).one()
                    .switchIfEmpty(Mono.error(ApiExceptions.conflict("They were nudged recently. Try again in five minutes.")))
                    .doOnNext(ignored -> {
                        var data=Map.of("type","HUUD_SPACE","huudSpaceId",huud.toString(),"event","nudged");
                        inbox.notify(target,Map.of("type","HUUD_SPACE","data",Map.of("huudSpaceId",huud.toString(),"event","nudged","by",sender.toString())));
                        push.sendToUsers(Set.of(target),"Come back to The Huud",names.getValue()+" invited you back to "+names.getKey()+". Tap to join.",data);
                    })).then();
    }
}
