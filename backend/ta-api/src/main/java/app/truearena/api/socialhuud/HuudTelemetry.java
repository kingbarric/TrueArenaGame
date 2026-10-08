package app.truearena.api.socialhuud;

import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.ReactiveTransactionManager;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.Mono;
import java.util.UUID;

/** Basic product analytics use durable events and audience samples, not private game state. */
@Component
public class HuudTelemetry {
    private final DatabaseClient db;
    private final TransactionalOperator tx;
    public HuudTelemetry(DatabaseClient db,ReactiveTransactionManager manager) {
        this.db=db;this.tx=TransactionalOperator.create(manager);
    }
    public Mono<Void> completed(UUID room) {
        return tx.transactional(db.sql("""
            UPDATE huud_sessions SET activity='results',last_activity_at=now()
            WHERE current_room_id=:room AND status='active' AND activity='playing'
            RETURNING id,owner_id,activity_version
            """).bind("room",room).fetch().one().flatMap(h->
            db.sql("INSERT INTO huud_events(huud_id,actor_id,room_id,activity_version,kind) VALUES(:huud,:owner,:room,:version,'GAME_COMPLETED')")
                .bind("huud",h.get("id")).bind("owner",h.get("owner_id")).bind("room",room).bind("version",h.get("activity_version"))
                .fetch().rowsUpdated().then(capture((UUID)h.get("id"),room))));
    }
    public Mono<Void> capture(UUID huud,UUID room) {
        return db.sql("""
            INSERT INTO huud_game_audience(room_id,huud_id,user_id,population)
            SELECT :room,:huud,user_id,'participant' FROM huud_members WHERE huud_id=:huud AND status='participant'
            UNION ALL
            SELECT :room,:huud,v.user_id,'viewer' FROM huud_viewers v WHERE v.huud_id=:huud
              AND v.last_seen_at>now()-interval '90 seconds'
              AND NOT EXISTS(SELECT 1 FROM huud_members m WHERE m.huud_id=:huud AND m.user_id=v.user_id AND m.status='participant')
            ON CONFLICT(room_id,user_id) DO NOTHING
            """).bind("huud",huud).bind("room",room).fetch().rowsUpdated().then();
    }
    public Mono<Void> sampleRetention() {
        return db.sql("""
            UPDATE huud_game_audience a SET sampled_at=now(),retained=
              EXISTS(SELECT 1 FROM huud_members m JOIN huud_sessions h ON h.id=m.huud_id
                WHERE m.huud_id=a.huud_id AND h.status='active' AND m.user_id=a.user_id AND m.status='participant'
                  AND m.last_seen_at>now()-interval '90 seconds')
              OR EXISTS(SELECT 1 FROM huud_viewers v JOIN huud_sessions h ON h.id=v.huud_id
                WHERE v.huud_id=a.huud_id AND h.status='active' AND v.user_id=a.user_id AND v.last_seen_at>now()-interval '90 seconds')
            WHERE a.sampled_at IS NULL AND a.finished_at<now()-interval '30 seconds'
            """).fetch().rowsUpdated().then();
    }
}
