package app.truearena.api.storage;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.context.ApplicationEventPublisher;

/** Durable outbox: an R2 outage must neither lose deletion work nor roll back erasure. */
@Component
public class AccountMediaErasure {
    private static final Logger log=LoggerFactory.getLogger(AccountMediaErasure.class);
    private final DatabaseClient db;
    private final ObjectStorage storage;
    private final ApplicationEventPublisher events;
    private final AtomicBoolean running=new AtomicBoolean();
    public record Erased(String key) {}
    public AccountMediaErasure(DatabaseClient db,ObjectStorage storage,ApplicationEventPublisher events) {
        this.db=db; this.storage=storage; this.events=events;
    }

    @Scheduled(fixedDelay=30000, initialDelay=30000)
    public void tick() {
        if (!storage.enabled() || !running.compareAndSet(false,true)) return;
        drain().doFinally(ignored -> running.set(false))
                .subscribe(ignored -> {}, error -> log.warn("Account media erasure will be retried"));
    }

    public Mono<Void> drain() {
        return db.sql("SELECT object_key FROM account_media_erasure ORDER BY requested_at LIMIT 100")
                .map((r,m) -> r.get("object_key",String.class)).all()
                .concatMap(key -> storage.delete(key).then(Mono.fromRunnable(() -> events.publishEvent(new Erased(key))))
                        .then(db.sql("DELETE FROM account_media_erasure WHERE object_key=:k")
                        .bind("k",key).fetch().rowsUpdated()))
                .then();
    }
}
