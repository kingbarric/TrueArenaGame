package app.truearena.api.friends;

import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.api.inbox.InboxRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Flux;
import reactor.test.StepVerifier;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class FriendServiceTest {

    private FriendRepository friends;
    private UserRepository users;
    private InboxRegistry inbox;
    private FriendService service;

    private final UUID alice = UUID.randomUUID();
    private final UUID bob = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        friends = mock(FriendRepository.class);
        users = mock(UserRepository.class);
        inbox = mock(InboxRegistry.class);
        service = new FriendService(friends, users, inbox);
    }

    private UserRow userRow(UUID id, String username) {
        return new UserRow(id, "Name", null, null, null, username, false, null, false, null, null, null, null, null);
    }

    @Test
    void onlineListOnlyDisclosesConnectedAcceptedFriends() {
        UUID pendingId = UUID.randomUUID();
        when(friends.findByLowUserIdOrHighUserId(alice, alice)).thenReturn(Flux.just(
                FriendRow.requested(alice, bob).accepted(),
                FriendRow.requested(alice, pendingId)));
        when(inbox.isOnline(bob)).thenReturn(true);
        when(inbox.isOnline(pendingId)).thenReturn(true);
        StepVerifier.create(service.onlineFriends(alice))
                .expectNext(bob)
                .verifyComplete();
    }

    @Test
    void onlineFriendsDoesNotReadTheLegacyAgentInventory() {
        when(friends.findByLowUserIdOrHighUserId(alice, alice)).thenReturn(Flux.empty());

        StepVerifier.create(service.onlineFriends(alice))
                .verifyComplete();

        verify(users, never()).findAgentsOf(alice);
    }

    @Test
    void sendingARequestToAnUnknownUsernameIs404() {
        when(users.findByUsername("nobody")).thenReturn(Mono.empty());
        StepVerifier.create(service.sendRequest(alice, "nobody"))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 404)
                .verify();
    }

    @Test
    void cannotFriendYourself() {
        when(users.findByUsername("alice")).thenReturn(Mono.just(userRow(alice, "alice")));
        StepVerifier.create(service.sendRequest(alice, "alice"))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 400)
                .verify();
    }

    @Test
    void firstRequestCreatesAPendingRowOrderedLowToHigh() {
        when(users.findByUsername("bob")).thenReturn(Mono.just(userRow(bob, "bob")));
        UUID low = FriendRow.lowerOf(alice, bob);
        UUID high = low.equals(alice) ? bob : alice;
        when(friends.findByLowUserIdAndHighUserId(low, high)).thenReturn(Mono.empty());
        when(friends.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));

        StepVerifier.create(service.sendRequest(alice, "bob")).verifyComplete();

        var captor = org.mockito.ArgumentCaptor.forClass(FriendRow.class);
        verify(friends, times(1)).save(captor.capture());
        FriendRow saved = captor.getValue();
        assertThat(saved.lowUserId()).isEqualTo(low);
        assertThat(saved.highUserId()).isEqualTo(high);
        assertThat(saved.status()).isEqualTo(FriendRow.PENDING);
        assertThat(saved.requestedBy()).isEqualTo(alice);
    }

    @Test
    void aSecondRequestFromTheSameSenderConflicts() {
        when(users.findByUsername("bob")).thenReturn(Mono.just(userRow(bob, "bob")));
        FriendRow existing = FriendRow.requested(alice, bob);
        UUID low = FriendRow.lowerOf(alice, bob);
        UUID high = low.equals(alice) ? bob : alice;
        when(friends.findByLowUserIdAndHighUserId(low, high)).thenReturn(Mono.just(existing));

        StepVerifier.create(service.sendRequest(alice, "bob"))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 409)
                .verify();
    }

    @Test
    void requestingBackWhenTheyAlreadyAskedYouAutoAccepts() {
        when(users.findByUsername("bob")).thenReturn(Mono.just(userRow(bob, "bob")));
        FriendRow existing = FriendRow.requested(bob, alice); // bob asked alice first
        UUID low = FriendRow.lowerOf(alice, bob);
        UUID high = low.equals(alice) ? bob : alice;
        when(friends.findByLowUserIdAndHighUserId(low, high)).thenReturn(Mono.just(existing));
        when(friends.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));

        StepVerifier.create(service.sendRequest(alice, "bob")).verifyComplete();

        var captor = org.mockito.ArgumentCaptor.forClass(FriendRow.class);
        verify(friends).save(captor.capture());
        assertThat(captor.getValue().status()).isEqualTo(FriendRow.ACCEPTED);
    }

    @Test
    void alreadyFriendsConflicts() {
        when(users.findByUsername("bob")).thenReturn(Mono.just(userRow(bob, "bob")));
        FriendRow existing = FriendRow.requested(alice, bob).accepted();
        UUID low = FriendRow.lowerOf(alice, bob);
        UUID high = low.equals(alice) ? bob : alice;
        when(friends.findByLowUserIdAndHighUserId(low, high)).thenReturn(Mono.just(existing));

        StepVerifier.create(service.sendRequest(alice, "bob"))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 409)
                .verify();
    }

    @Test
    void onlyTheRecipientMayAcceptARequest() {
        FriendRow row = FriendRow.requested(alice, bob); // alice asked bob
        UUID rowId = UUID.randomUUID();
        FriendRow withId = new FriendRow(rowId, row.lowUserId(), row.highUserId(), row.status(), row.requestedBy(), null);
        when(friends.findById(rowId)).thenReturn(Mono.just(withId));

        // alice (the requester) trying to accept her own request must fail
        StepVerifier.create(service.accept(rowId, alice))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 403)
                .verify();
    }

    @Test
    void theRecipientCanAcceptAPendingRequest() {
        FriendRow row = FriendRow.requested(alice, bob);
        UUID rowId = UUID.randomUUID();
        FriendRow withId = new FriendRow(rowId, row.lowUserId(), row.highUserId(), row.status(), row.requestedBy(), null);
        when(friends.findById(rowId)).thenReturn(Mono.just(withId));
        when(friends.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));

        StepVerifier.create(service.accept(rowId, bob)).verifyComplete();

        var captor = org.mockito.ArgumentCaptor.forClass(FriendRow.class);
        verify(friends).save(captor.capture());
        assertThat(captor.getValue().status()).isEqualTo(FriendRow.ACCEPTED);
    }

    @Test
    void decliningDeletesTheRow() {
        FriendRow row = FriendRow.requested(alice, bob);
        UUID rowId = UUID.randomUUID();
        FriendRow withId = new FriendRow(rowId, row.lowUserId(), row.highUserId(), row.status(), row.requestedBy(), null);
        when(friends.findById(rowId)).thenReturn(Mono.just(withId));
        when(friends.deleteById(rowId)).thenReturn(Mono.empty());

        StepVerifier.create(service.decline(rowId, bob)).verifyComplete();
        verify(friends).deleteById(rowId);
    }

    @Test
    void aStrangerCannotDeclineSomeoneElsesRequest() {
        FriendRow row = FriendRow.requested(alice, bob);
        UUID rowId = UUID.randomUUID();
        FriendRow withId = new FriendRow(rowId, row.lowUserId(), row.highUserId(), row.status(), row.requestedBy(), null);
        when(friends.findById(rowId)).thenReturn(Mono.just(withId));
        UUID stranger = UUID.randomUUID();

        StepVerifier.create(service.decline(rowId, stranger))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 403)
                .verify();
    }
}
