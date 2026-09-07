package app.truearena.api.room;

import app.truearena.api.room.RoomDtos.CreateRoomRequest;
import app.truearena.api.room.RoomDtos.JoinRoomRequest;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
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
    @Operation(summary = "Create a room (in a group, or ad-hoc if groupId is omitted)")
    public Mono<RoomView> create(@Valid @RequestBody CreateRoomRequest body) {
        return CurrentUser.id().flatMap(uid -> rooms.create(uid, body.groupId()));
    }

    @PostMapping("/join")
    @Operation(summary = "Join a room by its 6-char code")
    public Mono<RoomView> join(@Valid @RequestBody JoinRoomRequest body) {
        return CurrentUser.id().flatMap(uid -> rooms.join(body.code(), uid, body.nickname()));
    }

    @GetMapping("/{id}")
    public Mono<RoomView> one(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> rooms.get(id, uid));
    }
}
