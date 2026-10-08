package app.truearena.api.socialhuud;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component
public class SocialHuudExpiry {
    private final SocialHuudService huuds;
    private final HuudTelemetry telemetry;
    private final HuudGameBridge games;
    public SocialHuudExpiry(SocialHuudService huuds,HuudTelemetry telemetry,HuudGameBridge games) { this.huuds=huuds;this.telemetry=telemetry;this.games=games; }
    @Scheduled(fixedDelay=60000,initialDelay=60000)
    public void expire() {
        huuds.expire().then(telemetry.sampleRetention()).subscribe(v->{},e->org.slf4j.LoggerFactory.getLogger(getClass()).warn("Huud expiry failed",e));
    }
    @Scheduled(fixedDelay=10000,initialDelay=10000)
    public void retryVoice() { games.retryVoiceRevocations().subscribe(v->{},e->org.slf4j.LoggerFactory.getLogger(getClass()).warn("Huud voice retry failed",e)); }
}
