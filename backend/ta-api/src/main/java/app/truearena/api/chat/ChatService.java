package app.truearena.api.chat;

import app.truearena.api.chat.ChatDtos.ConversationView;
import app.truearena.api.chat.ChatDtos.MessageView;
import app.truearena.api.friends.FriendDtos.FriendUserView;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.push.PushNotificationService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.ConversationRepository;
import app.truearena.persistence.ConversationRow;
import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.GroupMemberRepository;
import app.truearena.persistence.GroupMemberRow;
import app.truearena.persistence.GroupRepository;
import app.truearena.persistence.GroupRow;
import app.truearena.persistence.MessageRepository;
import app.truearena.persistence.MessageRow;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * DM and group text chat, plus one special message kind — {@code
 * game_invite} — that carries a room's join code so the client can render a
 * "Join game" button straight in the thread (see {@code MessageView}).
 * Live push rides the same per-user `/ws/inbox` channel as `GAME_STARTING`
 * (see {@code InboxRegistry}): every send fans a {@code NEW_MESSAGE} frame
 * out to the conversation's other participant(s) right after the DB write,
 * so a conversation screen no longer has to poll. Best-effort and silent
 * for anyone not currently connected — same as the call-companion push —
 * they'll see the message on their next `listMessages` call regardless.
 */
@Service
public class ChatService {

    private final ConversationRepository conversations;
    private final MessageRepository messages;
    private final FriendRepository friends;
    private final GroupMemberRepository groupMembers;
    private final GroupRepository groups;
    private final RoomRepository rooms;
    private final RoomMemberRepository roomMembers;
    private final UserRepository users;
    private final InboxRegistry inbox;
    private final PushNotificationService push;

    public ChatService(ConversationRepository conversations, MessageRepository messages, FriendRepository friends,
                        GroupMemberRepository groupMembers, GroupRepository groups, RoomRepository rooms,
                        RoomMemberRepository roomMembers, UserRepository users, InboxRegistry inbox,
                        PushNotificationService push) {
        this.conversations = conversations;
        this.messages = messages;
        this.friends = friends;
        this.groupMembers = groupMembers;
        this.groups = groups;
        this.rooms = rooms;
        this.roomMembers = roomMembers;
        this.users = users;
        this.inbox = inbox;
        this.push = push;
    }

    // ---------------------------------------------------------------- opening a conversation

    public Mono<UUID> openDm(UUID selfId, UUID friendId) {
        UUID low = FriendRow.lowerOf(selfId, friendId);
        UUID high = low.equals(selfId) ? friendId : selfId;
        // A Cyber Agent shows up in the friends list — it's a player you can
        // put in a room — but it has no inbox. Say that plainly instead of
        // letting it fall through to "you can only message a friend", which
        // is baffling when you just picked it out of your friends.
        return users.findById(friendId)
                .filter(UserRow::isBot)
                .flatMap(bot -> Mono.<UUID>error(ApiExceptions.badRequest(
                        "Cyber Agents can't be messaged — add one to a huud with the agent button instead")))
                .switchIfEmpty(Mono.defer(() -> openDmWithPerson(selfId, low, high)));
    }

    private Mono<UUID> openDmWithPerson(UUID selfId, UUID low, UUID high) {
        return friends.findByLowUserIdAndHighUserId(low, high)
                .filter(row -> FriendRow.ACCEPTED.equals(row.status()))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("you can only message a friend")))
                .then(conversations.findByDmLowUserIdAndDmHighUserId(low, high))
                .switchIfEmpty(Mono.defer(() -> conversations.save(ConversationRow.dm(low, high))))
                .map(ConversationRow::id);
    }

    public Mono<UUID> openGroup(UUID selfId, UUID groupId) {
        return groupMembers.existsByGroupIdAndUserId(groupId, selfId)
                .filter(Boolean::booleanValue)
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("you're not a member of that group")))
                .then(conversations.findByGroupId(groupId))
                .switchIfEmpty(Mono.defer(() -> conversations.save(ConversationRow.group(groupId))))
                .map(ConversationRow::id);
    }

    // ---------------------------------------------------------------- listing

    public Flux<ConversationView> listConversations(UUID selfId) {
        return conversations.findAllForMember(selfId).concatMap(conv -> viewOf(conv, selfId));
    }

    /**
     * One conversation by id — the E2E-encrypted DM screen needs this to
     * learn the other participant's public key (already carried on {@code
     * ConversationView.other}, same DTO {@link #listConversations} uses)
     * without pulling the whole list just to find one row.
     */
    public Mono<ConversationView> get(UUID selfId, UUID conversationId) {
        return requireParticipant(selfId, conversationId)
                .then(conversations.findById(conversationId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such conversation")))
                .flatMap(conv -> viewOf(conv, selfId));
    }

    private Mono<ConversationView> viewOf(ConversationRow conv, UUID selfId) {
        Mono<MessageView> lastMessage = messages.findFirstByConversationIdOrderByCreatedAtDesc(conv.id())
                .flatMap(this::toMessageView);

        Mono<FriendUserView> other = ConversationRow.DM.equals(conv.type())
                ? users.findById(conv.otherDmUser(selfId)).map(ChatService::toUserView)
                : Mono.empty();

        Mono<String> groupName = ConversationRow.GROUP.equals(conv.type())
                ? groups.findById(conv.groupId()).map(GroupRow::name)
                : Mono.empty();

        // Mono.zip refuses null elements outright, so each genuinely-optional
        // field (a group has no "other" DM user, a DM has no group name, a
        // brand-new conversation has no last message yet) gets wrapped in
        // Optional to zip safely, then unwrapped back to a nullable DTO field.
        return Mono.zip(
                        other.map(Optional::of).defaultIfEmpty(Optional.empty()),
                        groupName.map(Optional::of).defaultIfEmpty(Optional.empty()),
                        lastMessage.map(Optional::of).defaultIfEmpty(Optional.empty()))
                .map(t -> new ConversationView(
                        conv.id(), conv.type(),
                        t.getT1().orElse(null),
                        conv.groupId(), t.getT2().orElse(null),
                        t.getT3().orElse(null)));
    }

    public Mono<ChatDtos.MessagePage> listMessages(UUID selfId, UUID conversationId, int limit) {
        return requireParticipant(selfId, conversationId)
                .thenMany(messages.findByConversationIdOrderByCreatedAtDesc(
                        conversationId, PageRequest.of(0, Math.min(Math.max(limit, 1), 100), Sort.unsorted())))
                .concatMap(this::toMessageView)
                .collectList()
                .map(list -> {
                    // oldest-first for the client to render top-to-bottom
                    java.util.Collections.reverse(list);
                    return new ChatDtos.MessagePage(list);
                });
    }

    // ---------------------------------------------------------------- sending

    public Mono<MessageView> sendText(UUID selfId, UUID conversationId, String text) {
        String trimmed = text == null ? "" : text.strip();
        if (trimmed.isEmpty()) {
            return Mono.error(ApiExceptions.badRequest("message can't be empty"));
        }
        String clipped = trimmed.length() > 2000 ? trimmed.substring(0, 2000) : trimmed;
        return requireParticipant(selfId, conversationId)
                .then(messages.save(MessageRow.text(conversationId, selfId, clipped)))
                .flatMap(this::toMessageView)
                .doOnNext(view -> pushNewMessage(conversationId, selfId, view));
    }

    public Mono<Void> sendGameInvite(UUID selfId, UUID conversationId, UUID roomId) {
        return requireParticipant(selfId, conversationId)
                .then(roomMembers.findByRoomIdAndUserId(roomId, selfId))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("you're not in that huud")))
                .then(rooms.findById(roomId))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such huud")))
                .flatMap(room -> messages.save(MessageRow.gameInvite(conversationId, selfId, roomId, room.code())))
                .flatMap(this::toMessageView)
                .doOnNext(view -> pushNewMessage(conversationId, selfId, view))
                .then();
    }

    /**
     * Fire-and-forget push to every other participant — never blocks the
     * send, never fails it. Everyone gets the live inbox frame if they're
     * connected; anyone who isn't also gets an OS push (see
     * {@link PushNotificationService#sendToUserIfOffline}).
     */
    private void pushNewMessage(UUID conversationId, UUID senderId, MessageView view) {
        boolean isInvite = MessageRow.GAME_INVITE.equals(view.kind());
        Map<String, String> data = new java.util.HashMap<>(Map.of(
                "type", isInvite ? "GAME_INVITE" : "NEW_MESSAGE",
                "conversationId", conversationId.toString()));
        if (view.roomId() != null) data.put("roomId", view.roomId().toString());
        if (view.roomCode() != null) data.put("roomCode", view.roomCode());

        users.findById(senderId).map(UserRow::displayName).defaultIfEmpty("Someone")
                .flatMapMany(senderName -> participantIds(conversationId, senderId)
                        .doOnNext(recipient -> {
                            inbox.notify(recipient, Map.of(
                                    "type", "NEW_MESSAGE",
                                    "data", Map.of(
                                            "conversationId", conversationId.toString(),
                                            "message", view)));
                            push.sendToUserIfOffline(recipient, senderName,
                                    isInvite ? senderName + " sent you a game invite" : view.text(), data);
                        }))
                .subscribe();
    }

    private Flux<UUID> participantIds(UUID conversationId, UUID excluding) {
        return conversations.findById(conversationId).flatMapMany(conv -> {
            if (ConversationRow.DM.equals(conv.type())) {
                UUID other = conv.dmLowUserId().equals(excluding) ? conv.dmHighUserId() : conv.dmLowUserId();
                return Flux.just(other);
            }
            return groupMembers.findByGroupId(conv.groupId())
                    .map(GroupMemberRow::userId)
                    .filter(id -> !id.equals(excluding));
        });
    }

    // ---------------------------------------------------------------- helpers

    private Mono<Void> requireParticipant(UUID selfId, UUID conversationId) {
        return conversations.findById(conversationId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such conversation")))
                .flatMap(conv -> {
                    if (ConversationRow.DM.equals(conv.type())) {
                        boolean in = conv.dmLowUserId().equals(selfId) || conv.dmHighUserId().equals(selfId);
                        return in ? Mono.empty() : Mono.error(ApiExceptions.forbidden("not your conversation"));
                    }
                    return groupMembers.existsByGroupIdAndUserId(conv.groupId(), selfId)
                            .filter(Boolean::booleanValue)
                            .switchIfEmpty(Mono.error(ApiExceptions.forbidden("not your conversation")))
                            .then();
                });
    }

    private Mono<MessageView> toMessageView(MessageRow m) {
        if (!MessageRow.GAME_INVITE.equals(m.kind())) {
            return Mono.just(new MessageView(m.id(), m.senderId(), m.kind(), m.text(), null, null, null, m.createdAt()));
        }
        return rooms.findById(m.roomId())
                .map(room -> new MessageView(m.id(), m.senderId(), m.kind(), null, m.roomId(), m.roomCode(), room.gameType(), m.createdAt()))
                .defaultIfEmpty(new MessageView(m.id(), m.senderId(), m.kind(), null, m.roomId(), m.roomCode(), null, m.createdAt()));
    }

    private static FriendUserView toUserView(UserRow u) {
        return new FriendUserView(u.id(), u.displayName(), u.username(), u.avatarUrl(), u.publicKey(),
                u.botGameType(), u.botDifficulty());
    }
}
