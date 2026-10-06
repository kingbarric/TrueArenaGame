package app.truearena.api.calls;

import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.push.PushNotificationService;
import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.GroupMemberRepository;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.voice.LiveKitRoomAdmin;
import app.truearena.voice.LiveKitTokenService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CallRingServiceTest {

    private final FriendRepository friends = mock(FriendRepository.class);
    private final UserRepository users = mock(UserRepository.class);
    private final InboxRegistry inbox = mock(InboxRegistry.class);
    private final PushNotificationService push = mock(PushNotificationService.class);
    private final GroupMemberRepository groupMembers = mock(GroupMemberRepository.class);
    private final LiveKitTokenService tokens = mock(LiveKitTokenService.class);
    private final LiveKitRoomAdmin voice = mock(LiveKitRoomAdmin.class);
    private final CallRingService rings =
            new CallRingService(friends, groupMembers, users, inbox, push, tokens, voice);

    private final UUID caller = UUID.randomUUID();
    private final UUID friend = UUID.randomUUID();

    private void friendsWith(String status) {
        UUID low = FriendRow.lowerOf(caller, friend);
        UUID high = low.equals(caller) ? friend : caller;
        FriendRow row = mock(FriendRow.class);
        when(row.status()).thenReturn(status);
        when(friends.findByLowUserIdAndHighUserId(low, high)).thenReturn(Mono.just(row));
        UserRow callerRow = mock(UserRow.class);
        when(callerRow.id()).thenReturn(caller);
        when(callerRow.displayName()).thenReturn("Eric Barima");
        when(users.findById(caller)).thenReturn(Mono.just(callerRow));
    }

    @Test
    @SuppressWarnings("unchecked")
    void ringsAFriendWhoHasTheAppOpenInApp() {
        friendsWith(FriendRow.ACCEPTED);
        when(inbox.isOnline(friend)).thenReturn(true);

        StepVerifier.create(rings.ring(caller, friend)).verifyComplete();

        ArgumentCaptor<Object> sent = ArgumentCaptor.forClass(Object.class);
        verify(inbox).notify(eq(friend), sent.capture());
        Map<String, Object> envelope = (Map<String, Object>) sent.getValue();
        assertThat(envelope.get("type")).isEqualTo("CALL_INCOMING");
        assertThat((Map<String, String>) envelope.get("data"))
                .containsEntry("callerId", caller.toString())
                .containsEntry("callerName", "Eric Barima");
        verify(push, never()).sendCallAlert(any(), anyString(), anyString(), anyMap());
    }

    @Test
    void wakesAFriendWhoseAppIsClosedWithACallPush() {
        friendsWith(FriendRow.ACCEPTED);
        when(inbox.isOnline(friend)).thenReturn(false);

        StepVerifier.create(rings.ring(caller, friend)).verifyComplete();

        verify(push).sendCallAlert(eq(friend), eq("Eric Barima"), eq("Incoming voice call"), anyMap());
    }

    @Test
    void onlyFriendsCanRing() {
        friendsWith("pending");
        StepVerifier.create(rings.ring(caller, friend)).verifyError();
        verify(inbox, never()).notify(any(), any());
    }

    @Test
    void onlySomeoneOnTheCallCanMuteOrDrop() {
        String room = CallRingService.dmRoom(caller, friend);
        when(voice.participantIds(room)).thenReturn(Mono.just(Set.of(friend.toString())));
        StepVerifier.create(rings.mute(caller, room, friend)).verifyError();
        StepVerifier.create(rings.remove(caller, room, friend)).verifyError();
        verify(voice, never()).muteAudio(anyString(), anyString());
        verify(voice, never()).remove(anyString(), anyString());
    }

    @Test
    void anyoneOnTheCallCanMuteAndDropSomeone() {
        String room = CallRingService.dmRoom(caller, friend);
        when(voice.participantIds(room)).thenReturn(Mono.just(Set.of(caller.toString(), friend.toString())));
        when(voice.muteAudio(room, friend.toString())).thenReturn(Mono.empty());
        when(voice.remove(room, friend.toString())).thenReturn(Mono.empty());
        StepVerifier.create(rings.mute(caller, room, friend)).verifyComplete();
        StepVerifier.create(rings.remove(caller, room, friend)).verifyComplete();
        verify(voice).muteAudio(room, friend.toString());
        verify(voice).remove(room, friend.toString());
    }

    @Test
    void addingAFriendLetsThemIntoTheRoomAndRingsThem() {
        UUID third = UUID.randomUUID();
        String room = CallRingService.dmRoom(caller, friend);
        when(voice.participantIds(room)).thenReturn(Mono.just(Set.of(caller.toString())));
        UUID low = FriendRow.lowerOf(caller, third);
        UUID high = low.equals(caller) ? third : caller;
        FriendRow row = mock(FriendRow.class);
        when(row.status()).thenReturn(FriendRow.ACCEPTED);
        when(friends.findByLowUserIdAndHighUserId(low, high)).thenReturn(Mono.just(row));
        friendsWith(FriendRow.ACCEPTED);
        when(inbox.isOnline(third)).thenReturn(true);

        StepVerifier.create(rings.canJoin(third, room)).expectNext(false).verifyComplete();
        StepVerifier.create(rings.invite(caller, room, third, "sealed-key")).verifyComplete();
        StepVerifier.create(rings.canJoin(third, room)).expectNext(true).verifyComplete();
        verify(inbox).notify(eq(third), any());
    }

    @Test
    void gameRoomsAreNotFairGame() {
        StepVerifier.create(rings.mute(caller, "game-" + UUID.randomUUID(), friend)).verifyError();
    }

    @Test
    @SuppressWarnings("unchecked")
    void declineTellsTheCaller() {
        friendsWith(FriendRow.ACCEPTED);
        StepVerifier.create(rings.decline(friend, caller)).verifyComplete();
        ArgumentCaptor<Object> sent = ArgumentCaptor.forClass(Object.class);
        verify(inbox).notify(eq(caller), sent.capture());
        assertThat(((Map<String, Object>) sent.getValue()).get("type")).isEqualTo("CALL_DECLINED");
    }
}
