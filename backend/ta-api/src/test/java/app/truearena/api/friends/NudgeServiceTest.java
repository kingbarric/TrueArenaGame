package app.truearena.api.friends;

import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.push.PushNotificationService;
import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class NudgeServiceTest {

    private final FriendRepository friends = mock(FriendRepository.class);
    private final UserRepository users = mock(UserRepository.class);
    private final InboxRegistry inbox = mock(InboxRegistry.class);
    private final PushNotificationService push = mock(PushNotificationService.class);
    private final UUID me = UUID.randomUUID();
    private final UUID friend = UUID.randomUUID();
    private Instant now = Instant.parse("2026-10-06T20:00:00Z");
    private final Clock clock = new Clock() {
        @Override public ZoneOffset getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(java.time.ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    };
    private final NudgeService nudges = new NudgeService(friends, users, inbox, push, clock);

    @BeforeEach
    void friendsWithEachOther() {
        UUID low = FriendRow.lowerOf(me, friend);
        UUID high = low.equals(me) ? friend : me;
        FriendRow row = mock(FriendRow.class);
        when(row.status()).thenReturn(FriendRow.ACCEPTED);
        when(friends.findByLowUserIdAndHighUserId(low, high)).thenReturn(Mono.just(row));
        UserRow self = mock(UserRow.class);
        when(self.displayName()).thenReturn("Eric Barima");
        when(users.findById(me)).thenReturn(Mono.just(self));
    }

    @Test
    void buzzesTheFriendInAppAndByPushWhenAway() {
        StepVerifier.create(nudges.nudge(me, friend)).verifyComplete();
        verify(inbox).notify(eq(friend), any());
        verify(push).sendToUserIfOffline(eq(friend), eq("Eric Barima nudged you 👋"), any(), anyMap());
    }

    @Test
    void oneNudgeEveryThirtySeconds() {
        StepVerifier.create(nudges.nudge(me, friend)).verifyComplete();
        now = now.plusSeconds(10);
        StepVerifier.create(nudges.nudge(me, friend)).verifyError();
        now = now.plusSeconds(25);
        StepVerifier.create(nudges.nudge(me, friend)).verifyComplete();
        verify(inbox, times(2)).notify(eq(friend), any());
    }

    @Test
    void cannotNudgeAStranger() {
        UUID stranger = UUID.randomUUID();
        UUID low = FriendRow.lowerOf(me, stranger);
        UUID high = low.equals(me) ? stranger : me;
        when(friends.findByLowUserIdAndHighUserId(low, high)).thenReturn(Mono.empty());
        StepVerifier.create(nudges.nudge(me, stranger)).verifyError();
        verify(inbox, never()).notify(eq(stranger), any());
    }
}
