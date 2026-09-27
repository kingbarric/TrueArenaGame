package app.truearena.api.group;

import app.truearena.api.group.GroupDtos.GroupMemberView;
import app.truearena.api.group.GroupDtos.GroupView;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.GroupMemberRepository;
import app.truearena.persistence.GroupMemberRow;
import app.truearena.persistence.GroupRepository;
import app.truearena.persistence.GroupRow;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

@Service
public class GroupService {

    private final GroupRepository groups;
    private final GroupMemberRepository members;

    public GroupService(GroupRepository groups, GroupMemberRepository members) {
        this.groups = groups;
        this.members = members;
    }

    public Mono<GroupView> create(String name, String avatarEmoji, UUID creatorId) {
        return groups.save(GroupRow.create(name, avatarEmoji, creatorId))
                .flatMap(g -> members.save(GroupMemberRow.of(g.id(), creatorId, "owner")).thenReturn(g))
                .map(GroupService::toView);
    }

    public Flux<GroupView> listMine(UUID userId) {
        return groups.findAllForMember(userId).map(GroupService::toView);
    }

    public Mono<GroupView> get(UUID groupId, UUID callerId) {
        return requireMember(groupId, callerId)
                .then(groups.findById(groupId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("group not found")))
                .map(GroupService::toView);
    }

    public Flux<GroupMemberView> members(UUID groupId, UUID callerId) {
        return requireMember(groupId, callerId)
                .thenMany(members.findByGroupId(groupId))
                .map(m -> new GroupMemberView(m.userId(), m.role(), m.joinedAt()));
    }

    public Mono<GroupMemberView> addMember(UUID groupId, UUID newUserId, UUID callerId) {
        return requireMember(groupId, callerId)
                .then(members.existsByGroupIdAndUserId(groupId, newUserId))
                .flatMap(exists -> exists
                        ? Mono.error(ApiExceptions.conflict("already a member"))
                        : members.save(GroupMemberRow.of(groupId, newUserId, "member")))
                .map(m -> new GroupMemberView(m.userId(), m.role(), m.joinedAt()));
    }

    private Mono<Void> requireMember(UUID groupId, UUID userId) {
        return members.existsByGroupIdAndUserId(groupId, userId)
                .flatMap(member -> member ? Mono.empty()
                        : Mono.error(ApiExceptions.forbidden("not a member of this group")));
    }

    private static GroupView toView(GroupRow g) {
        return new GroupView(g.id(), g.name(), g.avatarEmoji(), g.createdBy(), g.createdAt());
    }
}
