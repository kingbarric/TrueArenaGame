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
    void registerToken_savesANewRowWhenTheTokenIsUnseen() {
        UUID userId = UUID.randomUUID();
        when(tokens.findByToken("tok")).thenReturn(Mono.empty());
        when(tokens.save(any(DeviceTokenRow.class))).thenAnswer(inv -> Mono.just(inv.getArgument(0)));

        StepVerifier.create(service.registerToken(userId, DeviceTokenRow.ANDROID, "tok")).verifyComplete();

        verify(tokens).save(org.mockito.ArgumentMatchers.argThat(
                row -> row.userId().equals(userId) && row.platform().equals(DeviceTokenRow.ANDROID)));
    }

    @Test
    void registerToken_reassignsAnExistingTokenToTheNewUser() {
        UUID oldOwner = UUID.randomUUID();
        UUID newOwner = UUID.randomUUID();
        DeviceTokenRow existing = DeviceTokenRow.of(oldOwner, DeviceTokenRow.IOS, "tok");
        when(tokens.findByToken("tok")).thenReturn(Mono.just(existing));
        when(tokens.save(any(DeviceTokenRow.class))).thenAnswer(inv -> Mono.just(inv.getArgument(0)));

        StepVerifier.create(service.registerToken(newOwner, DeviceTokenRow.IOS, "tok")).verifyComplete();

        verify(tokens).save(org.mockito.ArgumentMatchers.argThat(row -> row.userId().equals(newOwner)));
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
}
