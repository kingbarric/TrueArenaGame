package app.truearena.api.auth;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/** Phase 2: pluggable SMS port. Dev impl just logs the code to the console. */
@Component
public class SmsSender {

    private static final Logger log = LoggerFactory.getLogger(SmsSender.class);

    public Mono<Void> send(String phone, String code) {
        return Mono.fromRunnable(() -> log.info("[SMS-STUB] OTP for {} = {}", phone, code));
    }
}
