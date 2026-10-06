package app.truearena.api.calls;

import app.truearena.api.calls.CallDtos.CallToken;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/calls")
@Tag(name = "calls")
public class CallController {

    private final CallService calls;
    private final CallRingService rings;

    public CallController(CallService calls, CallRingService rings) {
        this.calls = calls;
        this.rings = rings;
    }

    /** Ring a friend once you're in the call room. */
    @PostMapping("/dm/{friendUserId}/ring")
    public Mono<Void> ring(@PathVariable UUID friendUserId) {
        return CurrentUser.id().flatMap(uid -> rings.ring(uid, friendUserId));
    }

    /** Stop ringing — you hung up before they answered. */
    @PostMapping("/dm/{friendUserId}/cancel")
    public Mono<Void> cancel(@PathVariable UUID friendUserId) {
        return CurrentUser.id().flatMap(uid -> rings.cancel(uid, friendUserId));
    }

    /** Join a call room you were rung into (or belong to) — how an answered call connects. */
    @PostMapping("/rooms/{roomName}/token")
    public Mono<CallToken> joinToken(@PathVariable String roomName) {
        return CurrentUser.id().flatMap(uid -> rings.joinToken(uid, roomName));
    }

    /** Add a friend to the call you're on — their phone rings. */
    @PostMapping("/rooms/{roomName}/invite/{friendUserId}")
    public Mono<Void> invite(@PathVariable String roomName, @PathVariable UUID friendUserId,
                             @RequestBody(required = false) Map<String, String> body) {
        String mediaKey = body == null ? null : body.get("mediaKey");
        return CurrentUser.id().flatMap(uid -> rings.invite(uid, roomName, friendUserId, mediaKey));
    }

    /** Mute someone on the call you're on. */
    @PostMapping("/rooms/{roomName}/participants/{userId}/mute")
    public Mono<Void> mute(@PathVariable String roomName, @PathVariable UUID userId) {
        return CurrentUser.id().flatMap(uid -> rings.mute(uid, roomName, userId));
    }

    /** Drop someone from the call you're on. */
    @PostMapping("/rooms/{roomName}/participants/{userId}/remove")
    public Mono<Void> remove(@PathVariable String roomName, @PathVariable UUID userId) {
        return CurrentUser.id().flatMap(uid -> rings.remove(uid, roomName, userId));
    }

    /** Turn down a call from this friend. */
    @PostMapping("/dm/{callerUserId}/decline")
    public Mono<Void> decline(@PathVariable UUID callerUserId) {
        return CurrentUser.id().flatMap(uid -> rings.decline(uid, callerUserId));
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
