package app.truearena.api.huud;

import app.truearena.api.huud.HuudDtos.CreateChallengeRequest;
import app.truearena.api.huud.HuudDtos.CreatePostRequest;
import app.truearena.api.huud.HuudDtos.CreatedPost;
import app.truearena.api.huud.HuudDtos.FeedItem;
import app.truearena.api.huud.HuudDtos.Filter;
import app.truearena.api.huud.HuudDtos.Tab;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.support.ApiExceptions;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.Locale;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/huud")
@Tag(name = "huud")
public class HuudController {

    private final HuudService huud;

    private FeedPostService textPosts;

    @org.springframework.beans.factory.annotation.Autowired
    void setTextPosts(FeedPostService textPosts) {
        this.textPosts = textPosts;
    }

    public HuudController(HuudService huud) {
        this.huud = huud;
    }

    @GetMapping("/feed")
    @Operation(summary = "The Huud feed. tab: friends (Your Huud) | for_you. filter: all | open | wins | tournaments")
    public Flux<FeedItem> feed(@RequestParam(defaultValue = "friends") String tab,
                               @RequestParam(defaultValue = "all") String filter) {
        Tab t = parse(Tab.class, tab, "tab");
        Filter f = parse(Filter.class, filter, "filter");
        return CurrentUser.id().flatMapMany(uid -> huud.feed(uid, t, f));
    }

    @PostMapping("/text-posts")
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Post a short text to your friends' feed")
    public Mono<FeedItem> textPost(@RequestBody java.util.Map<String, String> body) {
        return CurrentUser.id().flatMap(user -> textPosts.post(user, body.get("body")));
    }

    @PostMapping("/text-posts/{id}/reaction")
    @Operation(summary = "React to a post (❤️ 👍 😂 😮 🔥 👏); the same emoji again takes it back")
    public Mono<HuudDtos.Reactions> react(@PathVariable UUID id, @RequestBody java.util.Map<String, String> body) {
        return CurrentUser.id().flatMap(user -> textPosts.react(user, id, body.get("emoji")));
    }

    @DeleteMapping("/text-posts/{id}")
    public Mono<Void> deleteTextPost(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> textPosts.delete(user, id));
    }

    @PostMapping("/posts")
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Post an open game request — creates its lobby room and returns it")
    public Mono<CreatedPost> post(@Valid @RequestBody CreatePostRequest body) {
        return CurrentUser.id().flatMap(uid -> huud.post(uid, body));
    }

    @PostMapping("/challenges")
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Challenge one player — creates a two-seat lobby room and notifies them")
    public Mono<CreatedPost> challenge(@Valid @RequestBody CreateChallengeRequest body) {
        return CurrentUser.id().flatMap(uid -> huud.challenge(uid, body));
    }

    @PostMapping("/posts/{id}/accept")
    @Operation(summary = "Accept a challenge addressed to you — joins its room")
    public Mono<RoomView> accept(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> huud.accept(uid, id));
    }

    @PostMapping("/posts/{id}/decline")
    @Operation(summary = "Decline a challenge addressed to you")
    public Mono<Void> decline(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> huud.decline(uid, id));
    }

    @DeleteMapping("/posts/{id}")
    @Operation(summary = "Take down your own open request or challenge")
    public Mono<Void> close(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> huud.close(uid, id));
    }

    private static <E extends Enum<E>> E parse(Class<E> type, String raw, String name) {
        try {
            return Enum.valueOf(type, raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw ApiExceptions.badRequest("unknown " + name + ": " + raw);
        }
    }
}
