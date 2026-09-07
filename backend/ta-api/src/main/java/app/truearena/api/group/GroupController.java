package app.truearena.api.group;

import app.truearena.api.group.GroupDtos.AddMemberRequest;
import app.truearena.api.group.GroupDtos.CreateGroupRequest;
import app.truearena.api.group.GroupDtos.GroupMemberView;
import app.truearena.api.group.GroupDtos.GroupView;
import app.truearena.api.support.CurrentUser;
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
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/groups")
@Tag(name = "groups")
public class GroupController {

    private final GroupService groups;

    public GroupController(GroupService groups) {
        this.groups = groups;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<GroupView> create(@Valid @RequestBody CreateGroupRequest body) {
        return CurrentUser.id().flatMap(uid -> groups.create(body.name(), uid));
    }

    @GetMapping
    public Flux<GroupView> mine() {
        return CurrentUser.id().flatMapMany(groups::listMine);
    }

    @GetMapping("/{id}")
    public Mono<GroupView> one(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> groups.get(id, uid));
    }

    @GetMapping("/{id}/members")
    public Flux<GroupMemberView> members(@PathVariable UUID id) {
        return CurrentUser.id().flatMapMany(uid -> groups.members(id, uid));
    }

    @PostMapping("/{id}/members")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<GroupMemberView> addMember(@PathVariable UUID id, @Valid @RequestBody AddMemberRequest body) {
        return CurrentUser.id().flatMap(uid -> groups.addMember(id, body.userId(), uid));
    }
}
