package app.truearena.api.admin;

import app.truearena.api.push.PushNotificationService;
import app.truearena.persistence.BroadcastNotificationRepository;
import app.truearena.persistence.BroadcastNotificationRow;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.Instant;

/**
 * Polls for admin-authored broadcasts whose send time has arrived — same
 * fixedDelay-poll shape as {@code ChampionshipService.tick()}. Not a
 * calendar cron, since an admin picks a one-off send time per broadcast
 * rather than this running a fixed weekly schedule.
 */
@Service
public class BroadcastSchedulerService {

    private static final Logger log = LoggerFactory.getLogger(BroadcastSchedulerService.class);

    private final BroadcastNotificationRepository broadcasts;
    private final PushNotificationService push;

    public BroadcastSchedulerService(BroadcastNotificationRepository broadcasts, PushNotificationService push) {
        this.broadcasts = broadcasts;
        this.push = push;
    }

    @Scheduled(fixedDelay = 15000)
    public void tick() {
        broadcasts.findDue()
                .concatMap(this::claimAndSend)
                .then()
                .subscribe(null, e -> log.warn("broadcast scheduler tick failed: {}", e.toString()));
    }

    /**
     * Claims the row (pending -> sending) before sending anything — not
     * after. {@code @Scheduled(fixedDelay=...)} only waits for this *method*
     * to return, not for the fire-and-forget reactive chain inside
     * {@code PushNotificationService} to finish, so without an atomic claim
     * two overlapping ticks could both see the same row as "pending" and
     * send it twice. A claim that affects 0 rows means another tick already
     * has it — this one just skips it.
     */
    private Mono<Void> claimAndSend(BroadcastNotificationRow b) {
        return broadcasts.claim(b.id()).flatMap(claimed -> {
            if (claimed == 0) return Mono.empty();
            return push.sendToAll(b.title(), b.body())
                    .flatMap(delivered -> broadcasts.save(delivered
                            ? b.withStatus(BroadcastNotificationRow.SENT, Instant.now())
                            : b.withStatus(BroadcastNotificationRow.FAILED, null)))
                    .onErrorResume(e -> {
                        log.warn("broadcast {} send failed: {}", b.id(), e.toString());
                        return broadcasts.save(b.withStatus(BroadcastNotificationRow.FAILED, null));
                    })
                    .then();
        });
    }
}
