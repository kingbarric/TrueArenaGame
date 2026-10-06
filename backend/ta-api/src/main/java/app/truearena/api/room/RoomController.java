package app.truearena.api.room;

import app.truearena.api.room.RoomDtos.CreateRoomRequest;
import app.truearena.api.room.RoomDtos.DiscoverableRoomView;
import app.truearena.api.room.RoomDtos.JoinRoomRequest;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.room.RoomDtos.WatchRoomRequest;
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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/rooms")
@Tag(name = "rooms")
public class RoomController {

    private final RoomService rooms;

    public RoomController(RoomService rooms) {
        this.rooms = rooms;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Create a room (in a group, or ad-hoc if groupId is omitted). stake is optional — omit for an unstaked room.")
    public Mono<RoomView> create(@Valid @RequestBody CreateRoomRequest body) {
        return CurrentUser.id().flatMap(uid -> rooms.create(uid, body.groupId(), body.gameType(), body.stake(), body.gameConfig(),
                Boolean.TRUE.equals(body.ranked())));
    }

    @DeleteMapping("/{id}")
    @Operation(summary = "Abandon a lobby before the game starts — host only, refunds any staked coins")
    public Mono<Void> abandon(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> rooms.abandon(id, uid));
    }

    @PostMapping("/{id}/leave-draughts")
    @Operation(summary = "End a Draughts game against a system Cyber Agent when leaving it")
    public Mono<Boolean> leaveDraughts(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> rooms.leaveBotDraughtsRoom(id, uid));
    }

    @PostMapping("/{id}/leave-whot")
    @Operation(summary = "End a Whot table containing only system Cyber Agents when leaving it")
    public Mono<Boolean> leaveWhot(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> rooms.leaveBotWhotRoom(id, uid));
    }

    @PostMapping("/{id}/leave-ludo")
    @Operation(summary = "Forfeit a Ludo seat and stop that table's Cyber Agent runtimes")
    public Mono<Boolean> leaveLudo(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> rooms.leaveLudoRoom(id, uid));
    }

    @PostMapping("/{id}/leave-goosi")
    @Operation(summary = "End an Oware pit against a system Cyber Agent when leaving it")
    public Mono<Boolean> leaveGoosi(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> rooms.leaveBotGoosiRoom(id, uid));
    }

    @PostMapping("/{id}/leave-wordbluff")
    @Operation(summary = "End a Word Bluff table containing only system Cyber Agents when leaving it")
    public Mono<Boolean> leaveWordBluff(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> rooms.leaveBotWordBluffRoom(id, uid));
    }

    @PostMapping("/join")
    @Operation(summary = "Join a room by its 6-char code")
    public Mono<RoomView> join(@Valid @RequestBody JoinRoomRequest body) {
        return CurrentUser.id().flatMap(uid -> rooms.join(body.code(), uid, body.nickname()));
    }

    @PostMapping("/watch")
    @Operation(summary = "Resolve an active room by huud code without taking a player seat")
    public Mono<RoomView> watch(@Valid @RequestBody WatchRoomRequest body) {
        return CurrentUser.id().flatMap(uid -> rooms.watch(body.code(), uid));
    }

    @GetMapping("/{id}")
    public Mono<RoomView> one(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> rooms.get(id, uid));
    }

    @GetMapping("/active")
    @Operation(summary = "The current player's most recent live room, if any")
    public Mono<RoomView> active() {
        return CurrentUser.id().flatMap(rooms::mostRecentActive);
    }

    @GetMapping("/discoverable")
    @Operation(summary = "Friends' games in progress right now, joinable as a spectator")
    public Flux<DiscoverableRoomView> discoverable() {
        return CurrentUser.id().flatMapMany(rooms::discoverable);
    }
}
