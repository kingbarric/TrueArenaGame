package app.truearena.api.support;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class PublicErrorAdviceTest {
 @Test void neverReturnsInternalSqlOrExceptionDetails() {
   var result = new PublicErrorAdvice().handle(new IllegalStateException("UPDATE huud_spaces SQL constraint password=secret"));
   assertThat(result.getStatusCode().value()).isEqualTo(500);
   assertThat(result.getBody()).containsEntry("message", PublicErrorAdvice.MESSAGE);
   assertThat(result.getBody().toString()).doesNotContain("SQL", "UPDATE", "secret", "constraint");
 }
 @Test void retainsStatusAndSafeMachineOutcomeForWatchingLive() {
   var result = new PublicErrorAdvice().handle(ApiExceptions.conflict("this huud is already playing — watch live instead"));
   assertThat(result.getStatusCode().value()).isEqualTo(409);
   assertThat(result.getBody()).containsEntry("code", "ALREADY_PLAYING").containsEntry("message", PublicErrorAdvice.MESSAGE);
 }
}
