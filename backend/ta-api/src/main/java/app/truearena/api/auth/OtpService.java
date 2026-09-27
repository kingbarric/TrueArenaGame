package app.truearena.api.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.security.SecureRandom;
import java.time.Duration;

/**
 * One-time codes over either channel — phone (SMS) or email — sharing the same Redis
 * store and dev bypass. The Redis key is just {@code otp:<identifier>}, so a phone and
 * an email can't collide as long as callers never mix which one they pass to
 * {@link #verify}.
 */
@Service
public class OtpService {

    private static final Duration TTL = Duration.ofMinutes(5);
    private static final SecureRandom RNG = new SecureRandom();

    private final ReactiveStringRedisTemplate redis;
    private final SmsSender sms;
    private final EmailSender email;
    private final String devBypassCode;

    public OtpService(ReactiveStringRedisTemplate redis, SmsSender sms, EmailSender email,
                      @Value("${truearena.auth.otp-dev-bypass-code:}") String devBypassCode) {
        this.redis = redis;
        this.sms = sms;
        this.email = email;
        this.devBypassCode = devBypassCode == null ? "" : devBypassCode;
    }

    public Mono<Void> requestPhone(String phone) {
        return requestVia(phone, code -> sms.send(phone, code));
    }

    public Mono<Void> requestEmail(String emailAddress) {
        return requestVia(emailAddress, code -> email.send(emailAddress, code));
    }

    private Mono<Void> requestVia(String identifier, java.util.function.Function<String, Mono<Void>> deliver) {
        String code = String.format("%06d", RNG.nextInt(1_000_000));
        return redis.opsForValue().set(key(identifier), code, TTL)
                .then(Mono.defer(() -> deliver.apply(code)));
    }

    /** Emits true when the code is valid; the stored code is consumed on success. */
    public Mono<Boolean> verify(String identifier, String code) {
        if (!devBypassCode.isBlank() && devBypassCode.equals(code)) {
            return redis.delete(key(identifier)).thenReturn(true);
        }
        return redis.opsForValue().get(key(identifier))
                .map(stored -> stored.equals(code))
                .defaultIfEmpty(false)
                .flatMap(ok -> ok ? redis.delete(key(identifier)).thenReturn(true) : Mono.just(false));
    }

    private static String key(String identifier) {
        return "otp:" + identifier;
    }
}
