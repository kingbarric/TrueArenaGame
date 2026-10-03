package app.truearena.api.friends;

import app.truearena.api.friends.FriendDtos.ContactMatchView;
import app.truearena.api.friends.FriendDtos.FriendRequestView;
import app.truearena.api.friends.FriendDtos.FriendRequestsView;
import app.truearena.api.friends.FriendDtos.FriendUserView;
import app.truearena.api.support.ApiExceptions;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class FriendService {

    private final FriendRepository friends;
    private final UserRepository users;
    private final InboxRegistry inbox;

    public FriendService(FriendRepository friends, UserRepository users, InboxRegistry inbox) {
        this.friends = friends;
        this.users = users;
        this.inbox = inbox;
    }

    /**
     * If the target already sent *us* a pending request, this accepts it
     * instead of erroring — two people wanting to be friends shouldn't need
     * one of them to notice and tap "accept" first.
     */
    public Mono<Void> sendRequest(UUID requesterId, String targetUsername) {
        return users.findByUsername(targetUsername)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no user with that username")))
                .flatMap(target -> sendRequestTo(requesterId, target));
    }

    /** Same flow as {@link #sendRequest}, just addressed by id — how a contact-match invite sends its request. */
    public Mono<Void> sendRequestToUserId(UUID requesterId, UUID targetUserId) {
        return users.findById(targetUserId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such user")))
                .flatMap(target -> sendRequestTo(requesterId, target));
    }

    private Mono<Void> sendRequestTo(UUID requesterId, UserRow target) {
        if (target.id().equals(requesterId)) {
            return Mono.error(ApiExceptions.badRequest("you can't friend yourself"));
        }
        // Kept as Mono<FriendRow> (never collapsed to Mono<Void>) until the very
        // end — switchIfEmpty must only ever catch "no existing pair row", never
        // an empty completion from further down the chain. And the fallback is
        // wrapped in defer() so `save` isn't called just to *construct* the
        // chain — only when this branch actually gets subscribed to.
        return pairOf(requesterId, target.id())
                .flatMap(existing -> {
                    if (FriendRow.ACCEPTED.equals(existing.status())) {
                        return Mono.error(ApiExceptions.conflict("already friends"));
                    }
                    if (existing.requestedBy().equals(requesterId)) {
                        return Mono.error(ApiExceptions.conflict("request already pending"));
                    }
                    // they already asked us — mutual want, accept immediately.
                    return friends.save(existing.accepted());
                })
                .switchIfEmpty(Mono.defer(() -> friends.save(FriendRow.requested(requesterId, target.id()))))
                .then();
    }

    public Mono<Void> accept(UUID friendRowId, UUID actingUserId) {
        return friends.findById(friendRowId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such request")))
                .flatMap(row -> {
                    if (row.requestedBy().equals(actingUserId) || !involves(row, actingUserId)) {
                        return Mono.error(ApiExceptions.forbidden("only the recipient can accept this request"));
                    }
                    if (!FriendRow.PENDING.equals(row.status())) {
                        return Mono.error(ApiExceptions.conflict("request isn't pending"));
                    }
                    return friends.save(row.accepted()).then();
                });
    }

    public Mono<Void> decline(UUID friendRowId, UUID actingUserId) {
        return friends.findById(friendRowId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such request")))
                .flatMap(row -> {
                    if (!involves(row, actingUserId)) {
                        return Mono.error(ApiExceptions.forbidden("not your request"));
                    }
                    return friends.deleteById(friendRowId);
                });
    }

    public Mono<Void> unfriend(UUID selfId, UUID otherUserId) {
        return pairOf(selfId, otherUserId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("not friends")))
                .flatMap(row -> friends.deleteById(row.id()));
    }

    /**
     * Friends, followed by the viewer's own Cyber Agents. An agent is a
     * player you can add to a room like any other, so it belongs in the
     * same list — but it's nobody else's friend, so it's appended here
     * rather than stored as a friend row.
     */
    public Flux<FriendUserView> listFriends(UUID selfId) {
        Flux<FriendUserView> people = friends.findByLowUserIdOrHighUserId(selfId, selfId)
                .filter(row -> FriendRow.ACCEPTED.equals(row.status()))
                .flatMap(row -> users.findById(row.otherUser(selfId)))
                .map(FriendService::toView);
        return people.concatWith(users.findAgentsOf(selfId).map(FriendService::toView));
    }

    /** Connected accepted friends and the viewer's own always-available Cyber Agents. */
    public Flux<UUID> onlineFriends(UUID selfId) {
        Flux<UUID> people = friends.findByLowUserIdOrHighUserId(selfId, selfId)
                .filter(row -> FriendRow.ACCEPTED.equals(row.status()))
                .map(row -> row.otherUser(selfId))
                .filter(inbox::isOnline);
        return people.concatWith(users.findAgentsOf(selfId).map(UserRow::id));
    }

    /**
     * "Invite from contacts" — the client sends every candidate phone-number
     * string it can normalize from the device's contact list (with the
     * user's OS-level permission already granted; nothing server-side
     * enforces that, it's a client-side gate), and this returns which of
     * them are already registered users, plus enough friend-status to let
     * the client show the right button (Add / Requested / Friends) without
     * a second round trip per contact.
     */
    public Flux<ContactMatchView> matchContacts(UUID selfId, List<String> candidatePhones) {
        Set<String> distinct = candidatePhones.stream()
                .filter(p -> p != null && !p.isBlank())
                .collect(Collectors.toSet());
        if (distinct.isEmpty()) {
            return Flux.empty();
        }
        return users.findByPhoneIn(distinct)
                .filter(u -> !u.id().equals(selfId))
                .concatMap(u -> pairOf(selfId, u.id())
                        .map(row -> toContactMatch(u, FriendRow.ACCEPTED.equals(row.status()), FriendRow.PENDING.equals(row.status())))
                        .defaultIfEmpty(toContactMatch(u, false, false)));
    }

    private static ContactMatchView toContactMatch(UserRow u, boolean isFriend, boolean requestPending) {
        return new ContactMatchView(u.phone(), u.id(), u.displayName(), u.username(), u.avatarUrl(), isFriend, requestPending);
    }

    private record PendingRow(boolean requestedByMe, FriendRequestView view) {
    }

    public Mono<FriendRequestsView> listRequests(UUID selfId) {
        return friends.findByLowUserIdOrHighUserId(selfId, selfId)
                .filter(row -> FriendRow.PENDING.equals(row.status()))
                .flatMap(row -> users.findById(row.requestedBy())
                        .map(requester -> new PendingRow(
                                row.requestedBy().equals(selfId),
                                new FriendRequestView(row.id(), toView(requester), row.createdAt()))))
                .collectList()
                .map(rows -> new FriendRequestsView(
                        rows.stream().filter(r -> !r.requestedByMe()).map(PendingRow::view).toList(),
                        rows.stream().filter(PendingRow::requestedByMe).map(PendingRow::view).toList()));
    }

    private Mono<FriendRow> pairOf(UUID a, UUID b) {
        UUID low = FriendRow.lowerOf(a, b);
        UUID high = low.equals(a) ? b : a;
        return friends.findByLowUserIdAndHighUserId(low, high);
    }

    private static boolean involves(FriendRow row, UUID userId) {
        return row.lowUserId().equals(userId) || row.highUserId().equals(userId);
    }

    private static FriendUserView toView(UserRow u) {
        return new FriendUserView(u.id(), u.displayName(), u.username(), u.avatarUrl(), u.publicKey(),
                u.botGameType(), u.botDifficulty());
    }
}
