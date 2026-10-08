package app.truearena.api.socialhuud;

import app.truearena.api.socialhuud.SocialHuudDtos.*;
import app.truearena.api.calls.CallDtos.CallToken;
import app.truearena.api.calls.CallRingService;
import app.truearena.api.support.CurrentUser;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/huuds/sessions")
public class SocialHuudController {
    private final SocialHuudService huuds;
    private final SocialHuudAccess access;
    private final HuudGameCatalog catalog;
    private final CallRingService calls;
    public SocialHuudController(SocialHuudService huuds,SocialHuudAccess access,HuudGameCatalog catalog,CallRingService calls) {
        this.huuds=huuds;this.access=access;this.catalog=catalog;this.calls=calls;
    }
    @PostMapping public Mono<View> create(@Valid @RequestBody Create body) { return CurrentUser.id().flatMap(u->huuds.create(u,body)); }
    @GetMapping("/owned") public Mono<View> owned() { return CurrentUser.id().flatMap(huuds::owned); }
    @GetMapping public Flux<View> discover() { return CurrentUser.id().flatMapMany(huuds::discover); }
    @GetMapping("/games") public List<GameOption> games() { return catalog.options(); }
    @PostMapping("/code") public Mono<View> code(@Valid @RequestBody Code code) { return CurrentUser.id().flatMap(u->huuds.watchCode(u,code.code())); }
    @PostMapping("/presence") public Mono<Void> presence() { return CurrentUser.id().flatMap(huuds::presence); }
    @GetMapping("/by-game/{roomId}") public Mono<View> byGame(@PathVariable UUID roomId) {
        return CurrentUser.id().flatMap(u->access.forGame(roomId).flatMap(id->huuds.view(id,u)));
    }
    @GetMapping("/{id}") public Mono<View> get(@PathVariable UUID id) { return CurrentUser.id().flatMap(u->huuds.view(id,u)); }
    @PostMapping("/{id}/heartbeat") public Mono<Void> heartbeat(@PathVariable UUID id) { return CurrentUser.id().flatMap(u->huuds.heartbeat(id,u)); }
    @DeleteMapping("/{id}/viewing") public Mono<Void> viewing(@PathVariable UUID id) { return CurrentUser.id().flatMap(u->huuds.stopViewing(id,u)); }
    @PostMapping("/{id}/join-request") public Mono<View> requestJoin(@PathVariable UUID id) { return CurrentUser.id().flatMap(u->huuds.requestJoin(id,u)); }
    @PostMapping("/{id}/join-requests/{userId}") public Mono<View> answerJoin(@PathVariable UUID id,@PathVariable UUID userId,@RequestBody Decision decision) {
        return CurrentUser.id().flatMap(u->huuds.answerJoin(id,u,userId,decision.accepted()));
    }
    @PostMapping("/{id}/invites/{userId}") public Mono<View> invite(@PathVariable UUID id,@PathVariable UUID userId) { return CurrentUser.id().flatMap(u->huuds.invite(id,u,userId)); }
    @PatchMapping("/{id}") public Mono<View> settings(@PathVariable UUID id,@Valid @RequestBody Settings settings) { return CurrentUser.id().flatMap(u->huuds.settings(id,u,settings)); }
    @PostMapping("/{id}/game") public Mono<View> game(@PathVariable UUID id,@Valid @RequestBody Game game) { return CurrentUser.id().flatMap(u->huuds.selectGame(id,u,game)); }
    @PostMapping("/{id}/hang-out") public Mono<View> hangOut(@PathVariable UUID id) { return CurrentUser.id().flatMap(u->huuds.hangOut(id,u)); }
    @PostMapping("/{id}/game-request") public Mono<View> gameRequest(@PathVariable UUID id,@Valid @RequestBody GameAction action) { return CurrentUser.id().flatMap(u->huuds.requestGame(id,u,action.activityVersion())); }
    @PostMapping("/{id}/roster/{userId}") public Mono<View> roster(@PathVariable UUID id,@PathVariable UUID userId,@Valid @RequestBody Selection selection) {
        return CurrentUser.id().flatMap(u->huuds.selectPlayer(id,u,userId,selection.selected(),selection.activityVersion()));
    }
    @PostMapping("/{id}/start") public Mono<Match> start(@PathVariable UUID id,@Valid @RequestBody GameAction action) { return CurrentUser.id().flatMap(u->huuds.start(id,u,action.activityVersion())); }
    @PostMapping("/{id}/rematch") public Mono<View> rematch(@PathVariable UUID id,@Valid @RequestBody GameAction action) { return CurrentUser.id().flatMap(u->huuds.rematch(id,u,action.activityVersion())); }
    @PostMapping("/{id}/voice/token") public Mono<CallToken> voice(@PathVariable UUID id) { return CurrentUser.id().flatMap(u->calls.joinToken(u,"huud-"+id)); }
    @PostMapping("/{id}/leave") public Mono<Void> leave(@PathVariable UUID id) { return CurrentUser.id().flatMap(u->huuds.leave(id,u)); }
    @DeleteMapping("/{id}/participants/{userId}") public Mono<View> remove(@PathVariable UUID id,@PathVariable UUID userId) { return CurrentUser.id().flatMap(u->huuds.remove(id,u,userId)); }
    @PostMapping("/{id}/participants/{userId}/mute") public Mono<Void> mute(@PathVariable UUID id,@PathVariable UUID userId) { return CurrentUser.id().flatMap(u->huuds.mute(id,u,userId)); }
    @PostMapping("/{id}/game-players/{userId}/remove") public Mono<View> removeFromGame(@PathVariable UUID id,@PathVariable UUID userId,@Valid @RequestBody GameAction action) {
        return CurrentUser.id().flatMap(u->huuds.removeFromGame(id,u,userId,action.activityVersion()));
    }
    @PostMapping("/{id}/end") public Mono<Void> end(@PathVariable UUID id) { return CurrentUser.id().flatMap(u->huuds.end(id,u)); }
    @GetMapping("/{id}/chat") public Flux<ChatMessage> chat(@PathVariable UUID id) { return CurrentUser.id().flatMapMany(u->huuds.chat(id,u)); }
    @PostMapping("/{id}/chat") public Mono<Void> send(@PathVariable UUID id,@Valid @RequestBody Message message) { return CurrentUser.id().flatMap(u->huuds.send(id,u,message.text())); }
    @PostMapping("/{id}/reports") public Mono<Void> report(@PathVariable UUID id,@Valid @RequestBody Report report) { return CurrentUser.id().flatMap(u->huuds.report(id,u,report)); }
    @PostMapping("/{id}/blocks/{userId}") public Mono<Void> block(@PathVariable UUID id,@PathVariable UUID userId) { return CurrentUser.id().flatMap(u->huuds.block(id,u,userId)); }
}
