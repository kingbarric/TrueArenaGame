package app.truearena.api.huudspace;

import app.truearena.api.huudspace.HuudSpaceDtos.AddGameRequest;
import app.truearena.api.huudspace.HuudSpaceDtos.CreateRequest;
import app.truearena.api.huudspace.HuudSpaceDtos.HistoryHuud;
import app.truearena.api.huudspace.HuudSpaceDtos.HuudSpaceView;
import app.truearena.api.huudspace.HuudSpaceDtos.JoinRequest;
import app.truearena.api.huudspace.HuudSpaceDtos.LiveHuud;
import app.truearena.api.huudspace.HuudSpaceDtos.UpdateRequest;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/huud-spaces")
@Tag(name = "Huud spaces", description = "The persistent place people hang out and play game after game")
public class HuudSpaceController {

    private final HuudSpaceService huuds;

    public HuudSpaceController(HuudSpaceService huuds) {
        this.huuds = huuds;
    }

    @PostMapping
    @Operation(summary = "Make a Huud (name + privacy), or reopen the one you already host")
    public Mono<HuudSpaceView> create(@Valid @RequestBody CreateRequest body) {
        return CurrentUser.id().flatMap(user -> huuds.create(user, body.name(), body.privacy()));
    }

    @GetMapping("/current")
    @Operation(summary = "The Huud you host right now — empty when you host none")
    public Mono<HuudSpaceView> current() {
        return CurrentUser.id().flatMap(huuds::current);
    }

    @GetMapping("/live")
    @Operation(summary = "Live Huuds you can look into: yours, your friends' and public ones")
    public Flux<LiveHuud> live() {
        return CurrentUser.id().flatMapMany(huuds::live);
    }

    @GetMapping("/history")
    @Operation(summary = "Huuds you made or joined, with who was there and what you played")
    public Flux<HistoryHuud> history() {
        return CurrentUser.id().flatMapMany(huuds::history);
    }

    @PostMapping("/join")
    @Operation(summary = "Join a Huud with its 6-letter code")
    public Mono<HuudSpaceView> joinByCode(@Valid @RequestBody JoinRequest body) {
        return CurrentUser.id().flatMap(user -> huuds.joinByCode(user, body.code()));
    }

    @PostMapping("/heartbeat")
    @Operation(summary = "Still here — keeps you (and, for a host, your Huud) from being handed on")
    public Mono<Void> heartbeat() {
        return CurrentUser.id().flatMap(huuds::heartbeat);
    }

    @GetMapping("/{id}")
    public Mono<HuudSpaceView> one(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> huuds.view(id, user));
    }

    @PatchMapping("/{id}")
    @Operation(summary = "Host only: rename the Huud or change who can find it")
    public Mono<HuudSpaceView> update(@PathVariable UUID id, @Valid @RequestBody UpdateRequest body) {
        return CurrentUser.id().flatMap(user -> huuds.update(user, id, body.name(), body.privacy()));
    }

    @PostMapping("/{id}/join")
    @Operation(summary = "Join a live Huud you can see on the Live tab")
    public Mono<HuudSpaceView> join(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> huuds.join(user, id));
    }

    @PostMapping("/{id}/leave")
    @Operation(summary = "Leave for good. A leaving host hands the Huud to whoever joined next.")
    public Mono<Void> leave(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> huuds.leave(user, id));
    }

    @PostMapping("/{id}/end")
    @Operation(summary = "Host only: end the Huud for everyone")
    public Mono<Void> end(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> huuds.end(user, id));
    }

    @PostMapping("/{id}/members/{userId}/remove")
    @Operation(summary = "Host only: take someone out of the Huud")
    public Mono<Void> remove(@PathVariable UUID id, @PathVariable UUID userId) {
        return CurrentUser.id().flatMap(user -> huuds.remove(user, id, userId));
    }

    @PostMapping("/{id}/game")
    @Operation(summary = "Host only: set up the next game in the Huud")
    public Mono<RoomView> addGame(@PathVariable UUID id, @Valid @RequestBody AddGameRequest body) {
        return CurrentUser.id().flatMap(user -> huuds.addGame(user, id, body.gameType()));
    }

    @DeleteMapping("/{id}/game")
    @Operation(summary = "Host only: put away a game that hasn't started or has finished")
    public Mono<HuudSpaceView> clearGame(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> huuds.clearGame(user, id));
    }
}
