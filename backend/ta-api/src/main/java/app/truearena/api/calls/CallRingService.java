package app.truearena.api.calls;

import app.truearena.api.calls.CallDtos.CallToken;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.push.PushNotificationService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.GroupMemberRepository;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.voice.LiveKitRoomAdmin;
import app.truearena.voice.LiveKitTokenService;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Everything about a friends-and-groups voice call beyond getting into it:
 * making phones ring, adding someone mid-call, and muting or dropping a
 * participant.
 *
 * <p>Ringing goes over the inbox socket when the friend has the app open,
 * and as a high-priority call push when they don't (see
 * {@link PushNotificationService#sendCallAlert}). Cancel and decline travel
 * back the same way so nobody is left ringing.
 *
 * <p>The persistent VoiceSession records who is on the call and its host.
 * Only that host may mute/remove other participants. Invitations follow the
 * session's invite permission and reuse the existing friendship checks.
 * Invitation records allow reconnects without tying voice to a game.
 */
@Service
public class CallRingService {

    /** How long an invitation into a call room stays good — covers token refreshes on reconnect. */
    static final Duration INVITE_TTL = Duration.ofHours(2);

    private final FriendRepository friends;
    private final GroupMemberRepository groupMembers;
    private final UserRepository users;
    private final InboxRegistry inbox;
    private final PushNotificationService push;
    private final LiveKitTokenService tokens;
    private final LiveKitRoomAdmin voice;

    @org.springframework.beans.factory.annotation.Autowired
    private VoiceSessionService sessions;

    /** roomName → (invited user → when the invitation lapses). */
    private final Map<String, Map<UUID, Instant>> invites = new ConcurrentHashMap<>();

    public CallRingService(FriendRepository friends, GroupMemberRepository groupMembers, UserRepository users,
                           InboxRegistry inbox, PushNotificationService push, LiveKitTokenService tokens,
                           LiveKitRoomAdmin voice) {
        this.friends = friends;
        this.groupMembers = groupMembers;
        this.users = users;
        this.inbox = inbox;
        this.push = push;
        this.tokens = tokens;
        this.voice = voice;
    }

    // ------------------------------------------------------------ ringing

    /** The caller is in their 1:1 call room and wants the friend's phone to ring. */
    public Mono<Void> ring(UUID callerId, UUID friendId) {
        String room = dmRoom(callerId, friendId);
        return requireFriends(callerId, friendId)
                .then(Mono.defer(() -> ringInto(room, callerId, friendId, null, null)));
    }

    /** The caller hung up before anyone answered. */
    public Mono<Void> cancel(UUID callerId, UUID friendId) {
        return requireFriends(callerId, friendId)
                .doOnSuccess(ignored -> inbox.notify(friendId, Map.of("type", "CALL_CANCELLED",
                        "data", Map.of("callerId", callerId.toString()))))
                .then();
    }

    /** The friend turned the call down — tell the caller so they stop waiting. */
    public Mono<Void> decline(UUID selfId, UUID callerId) {
        return requireFriends(selfId, callerId)
                .doOnSuccess(ignored -> inbox.notify(callerId, Map.of("type", "CALL_DECLINED",
                        "data", Map.of("by", selfId.toString()))))
                .then();
    }

    // ------------------------------------------------------- in the call

    /** A token for a call room you belong to or were invited into — how an answered ring joins. */
    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private app.truearena.api.socialhuud.SocialHuudAccess socialHuuds;

    public Mono<CallToken> joinToken(UUID userId, String roomName) {
        if(roomName!=null && roomName.startsWith("huud-") && socialHuuds!=null) {
            UUID id;
            try { id=UUID.fromString(roomName.substring(5)); }
            catch(IllegalArgumentException e) { return Mono.error(ApiExceptions.badRequest("invalid Huud voice room")); }
            return socialHuuds.requireParticipant(id,userId).then(users.findById(userId))
                .map(self -> new CallToken(roomName,tokens.mintToken(roomName,self.id().toString(),self.displayName()),tokens.wsUrl()));
        }
        return (sessions == null ? canJoin(userId, roomName) :
                sessions.removed(userId,roomName).flatMap(removed -> removed ? Mono.just(false) :
                sessions.isMember(userId,roomName).flatMap(member -> member ? Mono.just(true) :
                        sessions.approved(userId,roomName).flatMap(approved -> approved ? Mono.just(true) : canJoin(userId,roomName)))))
                .filter(Boolean::booleanValue)
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("you're not part of that call")))
                .then(users.findById(userId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such user")))
                .map(self -> new CallToken(roomName,
                        tokens.mintToken(roomName, self.id().toString(), self.displayName()), tokens.wsUrl()));
    }

    /**
     * Someone on the call adds one of their friends to it. For an end-to-end
     * encrypted 1:1 call the inviter passes {@code mediaKey}: the call's media
     * key, already encrypted on their phone to the invitee. The server only
     * relays it and can't read it.
     */
    public Mono<Void> invite(UUID requesterId, String roomName, UUID friendId, String mediaKey) {
        return requireOnCall(requesterId, roomName)
                .then(sessions == null ? Mono.empty() : sessions.requireInvitePermission(requesterId,roomName))
                .then(Mono.defer(() -> requireFriends(requesterId, friendId)))
                .then(Mono.defer(() -> ringInto(roomName, requesterId, friendId, "adding you to a call", mediaKey)));
    }

    /** Someone on the call mutes another participant. They can unmute themselves. */
    public Mono<Void> mute(UUID requesterId, String roomName, UUID targetId) {
        return requireOnCall(requesterId, roomName)
                .then(sessions == null ? Mono.empty() : sessions.requireOwner(requesterId,roomName))
                .then(Mono.defer(() -> voice.muteAudio(roomName, targetId.toString())));
    }

    /** Someone on the call drops another participant from it. */
    public Mono<Void> remove(UUID requesterId, String roomName, UUID targetId) {
        if (requesterId.equals(targetId)) {
            return Mono.error(ApiExceptions.badRequest("to leave, just hang up"));
        }
        return requireOnCall(requesterId, roomName)
                .then(sessions == null ? Mono.empty() : sessions.requireOwner(requesterId,roomName))
                .doOnSuccess(ignored -> {
                    Map<UUID, Instant> invited = invites.get(roomName);
                    if (invited != null) invited.remove(targetId);
                })
                .then(Mono.defer(() -> voice.remove(roomName, targetId.toString())))
                .then(sessions == null ? Mono.empty() : sessions.removeMembership(targetId,roomName));
    }

    // ------------------------------------------------------------ helpers

    private Mono<Void> ringInto(String roomName, UUID callerId, UUID friendId, String why, String mediaKey) {
        invites.computeIfAbsent(roomName, k -> new ConcurrentHashMap<>())
                .put(friendId, Instant.now().plus(INVITE_TTL));
        return (sessions == null ? Mono.<Void>empty() : sessions.recordInvite(roomName,friendId))
                .then(users.findById(callerId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such user")))
                .doOnNext(caller -> {
                    Map<String, String> data = callData(caller, roomName);
                    if (mediaKey != null && !mediaKey.isBlank()) {
                        data.put("mediaKey", mediaKey);
                    }
                    inbox.notify(friendId, Map.of("type", "CALL_INCOMING", "data", data));
                    if (!inbox.isOnline(friendId)) {
                        push.sendCallAlert(friendId, caller.displayName(),
                                why == null ? "Incoming voice call" : caller.displayName() + " is " + why, data);
                    }
                })
                .then();
    }

    Mono<Boolean> canJoin(UUID userId, String roomName) {
        Instant until = invites.getOrDefault(roomName, Map.of()).get(userId);
        if (until != null && until.isAfter(Instant.now())) {
            return Mono.just(true);
        }
        if (roomName.startsWith("dm-") && roomName.length() == 3 + 36 + 1 + 36) {
            try {
                UUID a = UUID.fromString(roomName.substring(3, 39));
                UUID b = UUID.fromString(roomName.substring(40));
                if (!userId.equals(a) && !userId.equals(b)) return Mono.just(false);
                return requireFriends(a, b).thenReturn(true).onErrorReturn(false);
            } catch (IllegalArgumentException e) {
                return Mono.just(false);
            }
        }
        if (roomName.startsWith("group-")) {
            try {
                return groupMembers.existsByGroupIdAndUserId(UUID.fromString(roomName.substring(6)), userId);
            } catch (IllegalArgumentException e) {
                return Mono.just(false);
            }
        }
        return Mono.just(false); // game voice has its own rules — see CallService
    }

    private Mono<Void> requireOnCall(UUID userId, String roomName) {
        if (sessions != null) return sessions.isMember(userId,roomName)
                .filter(Boolean::booleanValue).switchIfEmpty(Mono.error(ApiExceptions.forbidden("only people on the call can do that"))).then();
        if (!roomName.startsWith("dm-") && !roomName.startsWith("group-")) {
            return Mono.error(ApiExceptions.forbidden("that isn't a friends or group call"));
        }
        return voice.participantIds(roomName)
                .filter(ids -> ids.contains(userId.toString()))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("only people on the call can do that")))
                .then();
    }

    private Mono<FriendRow> requireFriends(UUID a, UUID b) {
        UUID low = FriendRow.lowerOf(a, b);
        UUID high = low.equals(a) ? b : a;
        return friends.findByLowUserIdAndHighUserId(low, high)
                .filter(row -> FriendRow.ACCEPTED.equals(row.status()))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("you can only call a friend")));
    }

    static String dmRoom(UUID a, UUID b) {
        UUID low = FriendRow.lowerOf(a, b);
        UUID high = low.equals(a) ? b : a;
        return "dm-" + low + "-" + high;
    }

    private static Map<String, String> callData(UserRow caller, String roomName) {
        Map<String, String> data = new HashMap<>();
        data.put("type", "INCOMING_CALL");
        data.put("roomName", roomName);
        data.put("callerId", caller.id().toString());
        data.put("callerName", caller.displayName());
        if (caller.avatarUrl() != null && !caller.avatarUrl().isBlank()) {
            data.put("callerAvatar", caller.avatarUrl());
        }
        // Lets the answering phone derive the same end-to-end media key the
        // caller used for a 1:1 (or unwrap the one an inviter sent).
        if (caller.publicKey() != null && !caller.publicKey().isBlank()) {
            data.put("callerPublicKey", caller.publicKey());
        }
        return data;
    }
}
