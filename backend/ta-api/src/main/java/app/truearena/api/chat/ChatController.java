package app.truearena.api.chat;

import app.truearena.api.chat.ChatDtos.ConversationView;
import app.truearena.api.chat.ChatDtos.MessagePage;
import app.truearena.api.chat.ChatDtos.MessageView;
import app.truearena.api.chat.ChatDtos.SendGameInviteRequest;
import app.truearena.api.chat.ChatDtos.SendTextRequest;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
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

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
@Tag(name = "chat")
public class ChatController {

    private final ChatService chat;

    public ChatController(ChatService chat) {
        this.chat = chat;
    }

    @PostMapping("/conversations/dm/{friendUserId}")
    public Mono<Map<String, UUID>> openDm(@PathVariable UUID friendUserId) {
        return CurrentUser.id().flatMap(uid -> chat.openDm(uid, friendUserId)).map(id -> Map.of("conversationId", id));
    }

    @PostMapping("/conversations/groups/{groupId}")
    public Mono<Map<String, UUID>> openGroup(@PathVariable UUID groupId) {
        return CurrentUser.id().flatMap(uid -> chat.openGroup(uid, groupId)).map(id -> Map.of("conversationId", id));
    }

    @GetMapping("/conversations")
    public Flux<ConversationView> list() {
        return CurrentUser.id().flatMapMany(chat::listConversations);
    }

    @GetMapping("/conversations/{id}")
    public Mono<ConversationView> one(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(uid -> chat.get(uid, id));
    }

    @GetMapping("/conversations/{id}/messages")
    public Mono<MessagePage> messages(@PathVariable UUID id, @RequestParam(defaultValue = "50") int limit) {
        return CurrentUser.id().flatMap(uid -> chat.listMessages(uid, id, limit));
    }

    @PostMapping("/conversations/{id}/messages")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<MessageView> sendText(@PathVariable UUID id, @Valid @RequestBody SendTextRequest body) {
        return CurrentUser.id().flatMap(uid -> chat.sendText(uid, id, body.text()));
    }

    @PostMapping("/conversations/{id}/invites")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<Void> sendGameInvite(@PathVariable UUID id, @RequestBody SendGameInviteRequest body) {
        return CurrentUser.id().flatMap(uid -> chat.sendGameInvite(uid, id, body.roomId()));
    }
}
