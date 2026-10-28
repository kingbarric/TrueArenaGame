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
 @Test void reservedReviewerDoesNotSendMailOrFallThroughToDevelopmentBypass() {
   var env = new MockEnvironment().withProperty("spring.profiles.active", "prod")
       .withProperty("truearena.auth.reviewer-email", "review@example.com");
   var otp = new OtpService(redis, sms, email, "123456", "", env);
   StepVerifier.create(otp.requestEmail("review@example.com")).verifyComplete();
   StepVerifier.create(otp.verify("review@example.com", "123456")).expectNext(false).verifyComplete();
   verifyNoInteractions(redis, sms, email);
 }

 @Test void separateAppleAndExistingReviewerCodesStayScopedAndNeverSendMail() throws Exception {
   var env = new MockEnvironment().withProperty("spring.profiles.active", "prod");
   for (var entry : java.util.Map.of("reviewer", "482915", "apple-reviewer", "739182").entrySet()) {
     String prefix = "truearena.auth." + entry.getKey();
     env.withProperty(prefix + "-email", entry.getKey() + "@example.com")
        .withProperty(prefix + "-code-sha256", java.util.HexFormat.of().formatHex(
           java.security.MessageDigest.getInstance("SHA-256").digest(entry.getValue().getBytes(java.nio.charset.StandardCharsets.UTF_8))))
        .withProperty(prefix + "-expires-at", "never");
   }
   @SuppressWarnings("unchecked")
   org.springframework.data.redis.core.ReactiveValueOperations<String,String> values = mock(org.springframework.data.redis.core.ReactiveValueOperations.class);
   when(redis.opsForValue()).thenReturn(values);
   when(values.increment(anyString())).thenReturn(Mono.just(2L));
   when(values.get("otp:ordinary@example.com")).thenReturn(Mono.empty());
   var otp = new OtpService(redis, sms, email, "", "", env);
   StepVerifier.create(otp.requestEmail("apple-reviewer@example.com")).verifyComplete();
   StepVerifier.create(otp.requestEmail("reviewer@example.com")).verifyComplete();
   StepVerifier.create(otp.verify("apple-reviewer@example.com", "739182")).expectNext(true).verifyComplete();
   StepVerifier.create(otp.verify("reviewer@example.com", "482915")).expectNext(true).verifyComplete();
   StepVerifier.create(otp.verify("apple-reviewer@example.com", "482915")).expectNext(false).verifyComplete();
   StepVerifier.create(otp.verify("reviewer@example.com", "739182")).expectNext(false).verifyComplete();
   StepVerifier.create(otp.verify("ordinary@example.com", "739182")).expectNext(false).verifyComplete();
   verify(values, times(2)).increment("reviewer-otp-attempts:apple-reviewer@example.com");
   verify(values, times(2)).increment("reviewer-otp-attempts:reviewer@example.com");
   verifyNoInteractions(sms, email);
 }
 @Test void appleReviewerWithoutValidConfigurationCannotUseDevelopmentBypass() {
   var env = new MockEnvironment().withProperty("spring.profiles.active", "prod")
       .withProperty("truearena.auth.apple-reviewer-email", "apple@example.com");
   var otp = new OtpService(redis, sms, email, "123456", "", env);
   StepVerifier.create(otp.requestEmail("apple@example.com")).verifyComplete();
   StepVerifier.create(otp.verify("apple@example.com", "123456")).expectNext(false).verifyComplete();
   verifyNoInteractions(redis, sms, email);
 }
 @Test void appleReviewerDoesNotBypassTestEnvironmentAllowlist() {
   var env = new MockEnvironment().withProperty("spring.profiles.active", "test")
       .withProperty("truearena.auth.apple-reviewer-email", "apple@example.com");
   var otp = new OtpService(redis, sms, email, "123456", "approved@example.com", env);
   StepVerifier.create(otp.requestEmail("apple@example.com")).verifyError();
   StepVerifier.create(otp.verify("apple@example.com", "123456")).expectNext(false).verifyComplete();
   verifyNoInteractions(redis, sms, email);
 }
}
