package app.truearena.api.auth;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/** Pluggable email port, same pattern as {@link SmsSender}. Dev impl just logs the code. */
@Component
public class EmailSender {

    private static final Logger log = LoggerFactory.getLogger(EmailSender.class);

    public Mono<Void> send(String email, String code) {
        return Mono.fromRunnable(() -> log.info("[EMAIL-STUB] OTP for {} = {}", email, code));
    }
}
