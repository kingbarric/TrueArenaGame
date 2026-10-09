package app.truearena.api.huudspace;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class HuudSpaceExpiry {
    private static final Logger log = LoggerFactory.getLogger(HuudSpaceExpiry.class);
    private final HuudSpaceService huuds;

    public HuudSpaceExpiry(HuudSpaceService huuds) {
        this.huuds = huuds;
    }

    @Scheduled(fixedDelay = 30000, initialDelay = 30000)
    public void expire() {
        huuds.expire().subscribe(v -> { }, e -> log.warn("Huud expiry failed", e));
    }
}
