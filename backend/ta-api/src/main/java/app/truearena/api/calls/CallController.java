package app.truearena.api.calls;

import app.truearena.api.calls.CallDtos.CallToken;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/calls")
@Tag(name = "calls")
public class CallController {

    private final CallService calls;

    public CallController(CallService calls) {
        this.calls = calls;
    }

    @PostMapping("/dm/{friendUserId}/token")
    public Mono<CallToken> dmToken(@PathVariable UUID friendUserId) {
        return CurrentUser.id().flatMap(uid -> calls.dmCallToken(uid, friendUserId));
    }

    @PostMapping("/groups/{groupId}/token")
    public Mono<CallToken> groupToken(@PathVariable UUID groupId) {
        return CurrentUser.id().flatMap(uid -> calls.groupCallToken(uid, groupId));
    }

    @PostMapping("/whot/{roomId}/token")
    public Mono<CallToken> whotToken(@PathVariable UUID roomId) {
        return CurrentUser.id().flatMap(uid -> calls.whotCallToken(uid, roomId));
    }

    @PostMapping("/games/{roomId}/token")
    public Mono<CallToken> gameToken(@PathVariable UUID roomId) {
        return CurrentUser.id().flatMap(uid -> calls.gameCallToken(uid, roomId));
    }

    @PostMapping("/games/{roomId}/activate")
    public Mono<Void> activateSpectatorVoice(@PathVariable UUID roomId) {
        return CurrentUser.id().flatMap(uid -> calls.activateSpectatorVoice(uid, roomId));
    }
}
