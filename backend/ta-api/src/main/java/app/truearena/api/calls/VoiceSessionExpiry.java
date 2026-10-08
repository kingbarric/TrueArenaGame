package app.truearena.api.calls;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component
public class VoiceSessionExpiry {
    private final VoiceSessionService sessions;
    private static final org.slf4j.Logger log=org.slf4j.LoggerFactory.getLogger(VoiceSessionExpiry.class);
    public VoiceSessionExpiry(VoiceSessionService sessions) { this.sessions=sessions; }
    @Scheduled(fixedDelay=60000, initialDelay=60000)
    public void expire() { sessions.expireInactive().subscribe(v -> {}, e -> log.warn("Voice session expiry failed",e)); }
}
