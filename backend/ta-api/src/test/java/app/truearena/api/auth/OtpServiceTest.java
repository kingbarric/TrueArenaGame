package app.truearena.api.auth;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.mock.env.MockEnvironment;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;
import static org.mockito.Mockito.*;
class OtpServiceTest {
 final ReactiveStringRedisTemplate redis = mock(ReactiveStringRedisTemplate.class);
 final SmsSender sms = mock(SmsSender.class);
 final EmailSender email = mock(EmailSender.class);
 OtpService service(String profile) { return new OtpService(redis,sms,email,"123456","barric3g@gmail.com",new MockEnvironment().withProperty("spring.profiles.active",profile)); }
 @Test void bypassCannotAccessAnotherMirroredAccount() {
   StepVerifier.create(service("test").verify("other@example.com","123456")).expectNext(false).verifyComplete();
   StepVerifier.create(service("test").requestEmail("other@example.com")).verifyError();
   verifyNoInteractions(redis,sms,email);
 }
 @Test void approvedEmailMatchesWithoutCaseOrWhitespace() {
   when(redis.delete("otp:barric3g@gmail.com")).thenReturn(Mono.just(1L));
   StepVerifier.create(service("test").verify(" BARRIC3G@gmail.com ","123456")).expectNext(true).verifyComplete();
 }
 @Test void localDevelopmentBypassStillWorks() {
   when(redis.delete("otp:other@example.com")).thenReturn(Mono.just(1L));
   StepVerifier.create(service("local").verify("other@example.com","123456")).expectNext(true).verifyComplete();
 }
}
