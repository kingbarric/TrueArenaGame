package app.truearena.api.calls;

import app.truearena.api.calls.CallDtos.CallToken;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.GroupMemberRepository;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.UserRepository;
import app.truearena.room.RoomRuntimeRegistry;
import app.truearena.voice.LiveKitTokenService;
import app.truearena.voice.LiveKitRoomAdmin;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.util.UUID;

/**
 * Decides *who's allowed* into which LiveKit room, then hands off to
 * {@link LiveKitTokenService} to actually sign the token. A LiveKit room is
 * multi-party by default, so a 1:1 call and a group call are the exact same
 * mechanism underneath — the only difference is which room name and which
 * membership check gets used to get there.
 */
@Service
public class CallService {

    @org.springframework.beans.factory.annotation.Autowired
    private VoiceSessionService sessions;

    private final FriendRepository friends;
    private final GroupMemberRepository groupMembers;
    private final RoomMemberRepository roomMembers;
    private final RoomRepository rooms;
    private final UserRepository users;
    private final LiveKitTokenService tokens;
    private final RoomRuntimeRegistry runtimes;
    private final LiveKitRoomAdmin voiceAdmin;

    public CallService(FriendRepository friends, GroupMemberRepository groupMembers,
                       RoomMemberRepository roomMembers, RoomRepository rooms,
                       UserRepository users, LiveKitTokenService tokens,
                       RoomRuntimeRegistry runtimes, LiveKitRoomAdmin voiceAdmin) {
        this.friends = friends;
        this.groupMembers = groupMembers;
        this.roomMembers = roomMembers;
        this.rooms = rooms;
        this.users = users;
        this.tokens = tokens;
        this.runtimes = runtimes;
        this.voiceAdmin = voiceAdmin;
    }

    public Mono<CallToken> dmCallToken(UUID selfId, UUID friendId) {
        // Must use the same Postgres-agreeing ordering FriendRow does (see its
        // doc) so this actually finds the row `friends.requests` created.
        UUID low = FriendRow.lowerOf(selfId, friendId);
        UUID high = low.equals(selfId) ? friendId : selfId;
        return friends.findByLowUserIdAndHighUserId(low, high)
                .filter(row -> FriendRow.ACCEPTED.equals(row.status()))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("you can only call a friend")))
                .then(users.findById(selfId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such user")))
                .map(self -> tokenFor("dm-" + low + "-" + high, self.id(), self.displayName()));
    }

    public Mono<CallToken> groupCallToken(UUID selfId, UUID groupId) {
        return groupMembers.existsByGroupIdAndUserId(groupId, selfId)
                .filter(Boolean::booleanValue)
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("you're not a member of that group")))
                .then(users.findById(selfId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such user")))
                .map(self -> tokenFor("group-" + groupId, self.id(), self.displayName()));
    }

    public Mono<CallToken> whotCallToken(UUID selfId, UUID roomId) {
        return rooms.findById(roomId)
                .filter(room -> "whot".equals(room.gameType()) && "in_game".equals(room.status()))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no active Whot game")))
                .then(roomMembers.findByRoomIdAndUserId(roomId, selfId))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("only players can join Whot voice")))
                .then(users.findById(selfId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such user")))
                .map(self -> tokenFor("whot-" + roomId, self.id(), self.displayName()));
    }

    /** A single voice room per active game, with the same membership check for every mode. */
    public Mono<CallToken> gameCallToken(UUID selfId, UUID roomId) {
        return rooms.findById(roomId)
                .filter(room -> "in_game".equals(room.status()))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no active game")))
                .then(roomMembers.findByRoomIdAndUserId(roomId, selfId).hasElement())
                .flatMap(isPlayer -> {
                    if (!isPlayer && !spectatorCanTalk(roomId, selfId)) {
                        return Mono.error(ApiExceptions.forbidden(
                                "ask an active player to approve you for live talk"));
                    }
                    return users.findById(selfId)
                            .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such user")))
                            .flatMap(self -> (sessions == null ? Mono.just("game-" + roomId) : sessions.voiceRoomForGame(roomId).defaultIfEmpty("game-" + roomId))
                                    .flatMap(name -> {
                                        Mono<Boolean> allowed = name.startsWith("dm-") && sessions != null ? sessions.isMember(selfId,name) : Mono.just(true);
                                        return allowed.filter(Boolean::booleanValue)
                                                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("join the encrypted call by invitation first")))
                                                .map(ok -> new CallToken(name,tokens.mintToken(name,self.id().toString(),self.displayName(),isPlayer),tokens.wsUrl()));
                                    }));
                });
    }

    /** Elevate a connected spectator only after checking their current approval. */
    public Mono<Void> activateSpectatorVoice(UUID selfId, UUID roomId) {
        return rooms.findById(roomId)
                .filter(room -> "in_game".equals(room.status()))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no active game")))
                .then(Mono.defer(() -> spectatorCanTalk(roomId, selfId)
                        ? (sessions == null ? Mono.just("game-" + roomId) : sessions.voiceRoomForGame(roomId).defaultIfEmpty("game-" + roomId))
                                .flatMap(name -> voiceAdmin.setCanPublish(name, selfId.toString(), true)
                                        .then(Mono.defer(() -> spectatorCanTalk(roomId, selfId)
                                                ? Mono.empty()
                                                : sessions == null ? voiceAdmin.remove(name,selfId.toString())
                                                : voiceAdmin.setCanPublish(name,selfId.toString(),false))))
                        : Mono.error(ApiExceptions.forbidden("live-talk approval is no longer active"))));
    }

    private boolean spectatorCanTalk(UUID roomId, UUID userId) {
        String id = userId.toString();
        return runtimes.find(roomId)
                .map(rt -> rt.spectatorUserIds.contains(id)
                        && rt.spectatorVoiceSpeakers.contains(id)
                        && !rt.mutedSpectatorVoiceSpeakers.contains(id))
                .orElse(false);
    }

    private CallToken tokenFor(String roomName, UUID participantId, String participantName) {
        String jwt = tokens.mintToken(roomName, participantId.toString(), participantName);
        return new CallToken(roomName, jwt, tokens.wsUrl());
    }
}
