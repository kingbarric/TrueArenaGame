package app.truearena.api.push;

import app.truearena.api.inbox.InboxRegistry;
import app.truearena.persistence.DeviceTokenRepository;
import app.truearena.persistence.DeviceTokenRow;
import app.truearena.persistence.UserNotificationRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.core.env.Environment;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.timeout;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * No Spring context here — {@code messaging} (the Firebase bean) is never
 * field-injected outside a container, so these exercise exactly the
 * "Firebase isn't configured" stub path, same as {@code EmailSender}'s own
 * unit tests exercise its local-stub branch.
 */
class PushNotificationServiceTest {

    private final DeviceTokenRepository tokens = mock(DeviceTokenRepository.class);
    private final UserNotificationRepository history = mock(UserNotificationRepository.class);
    private final InboxRegistry inbox = mock(InboxRegistry.class);
    private final Environment environment = mock(Environment.class);
    private final PushNotificationService service =
            new PushNotificationService(tokens, history, inbox, new ObjectMapper(), environment);

    @Test
    void registerToken_rejectsAnUnknownPlatform() {
        StepVerifier.create(service.registerToken(UUID.randomUUID(), "windows-phone", "tok"))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse
                        && rse.getStatusCode().value() == 400)
                .verify();
    }

    @Test
    void registrationAndAccountSwitchUseOneAtomicOperation() {
        UUID first=UUID.randomUUID(), second=UUID.randomUUID();
        when(tokens.register(any(), org.mockito.ArgumentMatchers.eq(DeviceTokenRow.ANDROID),
                org.mockito.ArgumentMatchers.eq("tok"))).thenReturn(Mono.just(1));
        StepVerifier.create(service.registerToken(first, DeviceTokenRow.ANDROID, "tok")).verifyComplete();
        StepVerifier.create(service.registerToken(second, DeviceTokenRow.ANDROID, "tok")).verifyComplete();
        verify(tokens).register(first, DeviceTokenRow.ANDROID, "tok");
        verify(tokens).register(second, DeviceTokenRow.ANDROID, "tok");
        verify(tokens, never()).findByToken(any());
        verify(tokens, never()).save(any());
    }

    @Test
    void sendToUserIfOffline_skipsWhenTheRecipientHasALiveInboxSocket() {
        UUID userId = UUID.randomUUID();
        when(inbox.isOnline(userId)).thenReturn(true);

        service.sendToUserIfOffline(userId, "title", "body", Map.of());

        verify(tokens, never()).findByUserIdIn(any());
    }

    @Test
    void sendToUserIfOffline_looksUpTokensWhenTheRecipientIsOffline() {
        UUID userId = UUID.randomUUID();
        when(inbox.isOnline(userId)).thenReturn(false);
        when(tokens.findByUserIdIn(Set.of(userId))).thenReturn(reactor.core.publisher.Flux.empty());

        service.sendToUserIfOffline(userId, "title", "body", Map.of());

        // fire-and-forget, subscribed on boundedElastic — poll briefly rather than assert synchronously
        verify(tokens, timeout(1000)).findByUserIdIn(Set.of(userId));
    }

    @Test
    void sendToUsers_doesNothingForAnEmptyCollection() {
        service.sendToUsers(Set.of(), "title", "body", Map.of());
        verify(tokens, never()).findByUserIdIn(any());
    }
    @Test void testProfileBlocksAllPushAndCallsUnlessRecipientIsExplicitlyAllowed() {
        var env=new org.springframework.mock.env.MockEnvironment();env.setActiveProfiles("test");
        UUID allowed=UUID.randomUUID(), blocked=UUID.randomUUID();
        var disabled=new PushNotificationService(tokens,history,inbox,new ObjectMapper(),env);
        disabled.sendToUsers(Set.of(allowed),"title","body",Map.of());
        disabled.sendCallAlert(allowed,"title","body",Map.of());
        verify(tokens,never()).findByUserIdIn(any());
        env.setProperty("TEST_PUSH_ALLOWED_USER_IDS",allowed.toString());
        var restricted=new PushNotificationService(tokens,history,inbox,new ObjectMapper(),env);
        when(tokens.findByUserIdIn(java.util.List.of(allowed))).thenReturn(reactor.core.publisher.Flux.empty());
        restricted.sendToUsers(Set.of(allowed,blocked),"title","body",Map.of());
        restricted.sendCallAlert(blocked,"title","body",Map.of());
        verify(tokens,timeout(1000)).findByUserIdIn(java.util.List.of(allowed));
        verify(tokens,never()).findByUserIdIn(Set.of(blocked));
        when(tokens.findAll()).thenReturn(reactor.core.publisher.Flux.just(DeviceTokenRow.of(blocked,DeviceTokenRow.IOS,"blocked-token")));
        StepVerifier.create(restricted.sendToAll("title","body")).expectNext(true).verifyComplete();
        verify(history,never()).save(any());
    }

}
