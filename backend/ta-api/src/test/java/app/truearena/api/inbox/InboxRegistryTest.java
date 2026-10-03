package app.truearena.api.inbox;

import org.junit.jupiter.api.Test;
import reactor.core.publisher.Sinks;
import reactor.test.StepVerifier;

import java.util.Map;
import java.util.UUID;

class InboxRegistryTest {

    @Test
    void closingOldSocketDoesNotDisconnectReplacementOrClearItsCall() {
        InboxRegistry registry = new InboxRegistry();
        UUID userId = UUID.randomUUID();
        UUID companionId = UUID.randomUUID();
        Sinks.Many<Object> oldSocket = Sinks.many().unicast().onBackpressureBuffer();
        Sinks.Many<Object> newSocket = Sinks.many().unicast().onBackpressureBuffer();

        registry.connect(userId, oldSocket);
        org.assertj.core.api.Assertions.assertThat(registry.isOnline(userId)).isTrue();
        registry.joinCall(userId, "call-1");
        registry.connect(userId, newSocket);
        registry.joinCall(companionId, "call-1");
        registry.disconnect(userId, oldSocket);
        org.assertj.core.api.Assertions.assertThat(registry.isOnline(userId)).isTrue();

        Map<String, String> message = Map.of("type", "NEW_MESSAGE");
        registry.notify(userId, message);

        StepVerifier.create(newSocket.asFlux().take(1))
                .expectNext(message)
                .verifyComplete();
        org.assertj.core.api.Assertions.assertThat(registry.callCompanionsOf(companionId))
                .contains(userId);
        registry.disconnect(userId, newSocket);
        org.assertj.core.api.Assertions.assertThat(registry.isOnline(userId)).isFalse();
    }
}
