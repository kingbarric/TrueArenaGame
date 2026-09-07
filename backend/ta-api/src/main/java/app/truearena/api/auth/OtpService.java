package app.truearena.api.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.security.SecureRandom;
import java.time.Duration;

@Service
public class OtpService {

    private static final Duration TTL = Duration.ofMinutes(5);
    private static final SecureRandom RNG = new SecureRandom();

    private final ReactiveStringRedisTemplate redis;
    private final SmsSender sms;
    private final String devBypassCode;

    public OtpService(ReactiveStringRedisTemplate redis, SmsSender sms,
                      @Value("${truearena.auth.otp-dev-bypass-code:}") String devBypassCode) {
        this.redis = redis;
        this.sms = sms;
        this.devBypassCode = devBypassCode == null ? "" : devBypassCode;
    }

    public Mono<Void> request(String phone) {
        String code = String.format("%06d", RNG.nextInt(1_000_000));
        return redis.opsForValue().set(key(phone), code, TTL)
                .then(sms.send(phone, code));
    }

    /** Emits true when the code is valid; the stored code is consumed on success. */
    public Mono<Boolean> verify(String phone, String code) {
        if (!devBypassCode.isBlank() && devBypassCode.equals(code)) {
            return redis.delete(key(phone)).thenReturn(true);
        }
        return redis.opsForValue().get(key(phone))
                .map(stored -> stored.equals(code))
                .defaultIfEmpty(false)
                .flatMap(ok -> ok ? redis.delete(key(phone)).thenReturn(true) : Mono.just(false));
    }

    private static String key(String phone) {
        return "otp:" + phone;
    }
}
