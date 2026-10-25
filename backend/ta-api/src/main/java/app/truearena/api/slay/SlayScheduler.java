package app.truearena.api.slay;

import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicBoolean;

@Component
public class SlayScheduler {
    private final SlayService slay;
    private final AtomicBoolean running = new AtomicBoolean();

    public SlayScheduler(SlayService slay) {
        this.slay = slay;
    }

    @Scheduled(fixedDelay = 3000)
    public void tick() {
        if (!running.compareAndSet(false, true)) return;
        slay.ensureScheduled()
                .then(slay.tick())
                .doFinally(s -> running.set(false))
                .subscribe(
                        v -> {},
                        e ->
                                LoggerFactory.getLogger(getClass())
                                        .error("SlayHuud lifecycle tick failed", e));
    }
}
