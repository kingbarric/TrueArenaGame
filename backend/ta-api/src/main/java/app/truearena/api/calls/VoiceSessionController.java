package app.truearena.api.calls;
import app.truearena.api.support.ApiExceptions;
import app.truearena.api.support.CurrentUser;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import java.util.Map;
import java.util.UUID;
@RestController
@RequestMapping("/api/v1/calls/sessions")
public class VoiceSessionController {
    private final VoiceSessionService sessions;
    private final CallService calls;
    private final CallRingService rings;
    public VoiceSessionController(VoiceSessionService sessions, CallService calls, CallRingService rings) {
        this.sessions=sessions; this.calls=calls; this.rings=rings;
    }
    @GetMapping("/active") public Mono<VoiceSessionService.VoiceSession> active() { return CurrentUser.id().flatMap(sessions::active); }
    @GetMapping("/discoverable") public Flux<VoiceSessionService.VoiceSession> discover() { return CurrentUser.id().flatMapMany(sessions::discover); }
    @PostMapping("/join") public Mono<VoiceSessionService.VoiceSession> join(@RequestBody Map<String,String> body) {
        String name=body.get("roomName");
        if(name==null) return Mono.error(ApiExceptions.badRequest("roomName required"));
        return CurrentUser.id().flatMap(user -> authorize(user,name).then(sessions.join(user,name)));
    }
    private Mono<Void> authorize(UUID user,String name) {
        if(name.startsWith("game-") || name.startsWith("whot-")) {
            try { return calls.gameCallToken(user,UUID.fromString(name.substring(5)))
                    .filter(token -> token.roomName().equals(name))
                    .switchIfEmpty(Mono.error(ApiExceptions.conflict("join the game’s existing hangout"))).then(); }
            catch(IllegalArgumentException e) { return Mono.error(ApiExceptions.badRequest("invalid game voice room")); }
        }
        return rings.joinToken(user,name).then();
    }
    @PostMapping("/heartbeat") public Mono<Void> heartbeat() { return CurrentUser.id().flatMap(sessions::heartbeat); }
    @PostMapping("/mute") public Mono<Void> mute(@RequestBody Map<String,Boolean> body) {
        return CurrentUser.id().flatMap(user -> sessions.mute(user,Boolean.TRUE.equals(body.get("muted"))));
    }
    @PostMapping("/leave") public Mono<Void> leave(@RequestBody Map<String,String> body) {
        return CurrentUser.id().flatMap(user -> sessions.leave(user,body.get("roomName")));
    }
    @PostMapping("/delegate") public Mono<Void> delegate(@RequestBody Map<String,UUID> body) {
        if(body.get("userId")==null) return Mono.error(ApiExceptions.badRequest("choose the next host"));
        return CurrentUser.id().flatMap(user -> sessions.delegate(user,body.get("userId")));
    }
    @PostMapping("/end") public Mono<Void> end() { return CurrentUser.id().flatMap(sessions::end); }
    @PostMapping("/settings") public Mono<Void> settings(@RequestBody Map<String,String> body) {
        return CurrentUser.id().flatMap(user -> sessions.settings(user,body.get("privacy"),body.get("invitePermissions")));
    }
    @PostMapping("/{id}/request") public Mono<Void> request(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> sessions.requestJoin(user,id));
    }
    @PostMapping("/requests/{userId}/answer") public Mono<Void> answer(@PathVariable UUID userId,@RequestBody Map<String,Boolean> body) {
        return CurrentUser.id().flatMap(user -> sessions.answerRequest(user,userId,Boolean.TRUE.equals(body.get("approved"))));
    }
}
