package app.truearena.api.friends;

import app.truearena.api.friends.FriendDtos.ContactMatchRequest;
import app.truearena.api.friends.FriendDtos.ContactMatchView;
import app.truearena.api.friends.FriendDtos.FriendRequestsView;
import app.truearena.api.friends.FriendDtos.FriendUserView;
import app.truearena.api.friends.FriendDtos.SendFriendRequestBody;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/friends")
@Tag(name = "friends")
public class FriendController {

    private final FriendService friendService;

    public FriendController(FriendService friendService) {
        this.friendService = friendService;
    }

    @GetMapping
    public Flux<FriendUserView> list() {
        return CurrentUser.id().flatMapMany(friendService::listFriends);
    }

    @GetMapping("/online")
    public Flux<UUID> online() {
        return CurrentUser.id().flatMapMany(friendService::onlineFriends);
    }

    @GetMapping("/requests")
    public Mono<FriendRequestsView> requests() {
        return CurrentUser.id().flatMap(friendService::listRequests);
    }

    @PostMapping("/requests")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<Void> sendRequest(@Valid @RequestBody SendFriendRequestBody body) {
        return CurrentUser.id().flatMap(uid -> friendService.sendRequest(uid, body.username()));
    }

    @PostMapping("/requests/user/{userId}")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<Void> sendRequestToUser(@PathVariable UUID userId) {
        return CurrentUser.id().flatMap(uid -> friendService.sendRequestToUserId(uid, userId));
    }

    /** Contact-invite matching — the client already has the user's OS-level contacts permission before calling this. */
    @PostMapping("/contacts/match")
    public Flux<ContactMatchView> matchContacts(@Valid @RequestBody ContactMatchRequest body) {
        return CurrentUser.id().flatMapMany(uid -> friendService.matchContacts(uid, body.phones()));
    }

    @PostMapping("/requests/{id}/accept")
    public Mono<Void> accept(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> friendService.accept(id, uid));
    }

    @PostMapping("/requests/{id}/decline")
    public Mono<Void> decline(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> friendService.decline(id, uid));
    }

    @DeleteMapping("/{userId}")
    public Mono<Void> unfriend(@PathVariable UUID userId) {
        return CurrentUser.id().flatMap(uid -> friendService.unfriend(uid, userId));
    }
}
