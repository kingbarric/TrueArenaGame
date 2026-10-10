package app.truearena.api.slay;

import app.truearena.api.support.CurrentUser;
import app.truearena.engine.slay.SlayRules.*;

import org.springframework.core.io.buffer.DataBufferLimitException;
import org.springframework.core.io.buffer.DataBufferUtils;
import org.springframework.http.*;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.web.bind.annotation.*;

import reactor.core.publisher.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/slay")
public class SlayController {
    private final SlayService slay;
    private final SlayCatalog catalog;

    public SlayController(SlayService slay, SlayCatalog catalog) {
        this.slay = slay;
        this.catalog = catalog;
    }

    public record Purchase(String itemId) {}

    public record Choice(String entryId) {}

    public record Verdict(String entryId, boolean slay) {}

    public record Report(UUID lookId, String reason) {}

    public record Block(UUID userId) {}

    @GetMapping("/catalog")
    public SlayCatalog.Manifest catalog() {
        return catalog.manifest();
    }

    @GetMapping("/profile")
    public Mono<Map<String, Object>> profile() {
        return CurrentUser.id().flatMap(slay::profile);
    }

    @GetMapping("/wardrobe")
    public Mono<Set<String>> wardrobe() {
        return CurrentUser.id().flatMap(slay::wardrobe);
    }

    @PostMapping("/wardrobe/buy")
    public Mono<Void> buy(@RequestBody Purchase body) {
        return CurrentUser.id().flatMap(u -> slay.buy(u, body.itemId()));
    }

    @PostMapping("/looks")
    public Mono<SlayService.SavedLook> save(@RequestBody Look look) {
        return CurrentUser.id().flatMap(u -> slay.saveLook(u, look));
    }

    @GetMapping("/looks/{id}")
    public Mono<SlayService.RunwayLook> runwayLook(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(u -> slay.runwayLook(u, id));
    }

    /**
     * Raw JPEG bytes, not JSON: the size cap applies to this route alone, so the
     * global in-memory codec limit stays at its default.
     */
    @PostMapping(value = "/looks/{id}/snapshot", consumes = MediaType.IMAGE_JPEG_VALUE)
    public Mono<Void> snapshot(@PathVariable UUID id, ServerHttpRequest request) {
        return DataBufferUtils.join(request.getBody(), SlayService.MAX_SNAPSHOT_BYTES)
                .map(
                        buffer -> {
                            byte[] bytes = new byte[buffer.readableByteCount()];
                            buffer.read(bytes);
                            DataBufferUtils.release(buffer);
                            return bytes;
                        })
                .onErrorMap(
                        DataBufferLimitException.class,
                        e -> new IllegalArgumentException("Image must be at most 512 KB"))
                .defaultIfEmpty(new byte[0])
                .flatMap(bytes -> CurrentUser.id().flatMap(u -> slay.snapshot(u, id, bytes)));
    }

    @GetMapping("/looks/{id}/snapshot")
    public Mono<ResponseEntity<byte[]>> snapshot(@PathVariable UUID id) {
        return CurrentUser.id()
                .flatMap(u -> slay.image(u, id))
                .map(
                        bytes ->
                                ResponseEntity.ok()
                                        .contentType(SlayService.snapshotType(bytes))
                                        .body(bytes));
    }

    @PostMapping("/solo/{theme}/score")
    public Mono<Score> score(@PathVariable String theme, @RequestBody SlayService.Submit body) {
        return CurrentUser.id().flatMap(u -> slay.solo(u, theme, body.lookId()));
    }

    @GetMapping("/competitions")
    public Flux<Map<String, Object>> competitions() {
        return CurrentUser.id().flatMapMany(slay::list);
    }

    @PostMapping("/competitions")
    public Mono<Map<String, Object>> create(@RequestBody SlayService.Create body) {
        return CurrentUser.id().flatMap(u -> slay.create(u, body));
    }

    @GetMapping("/competitions/{id}")
    public Mono<Map<String, Object>> competition(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(u -> slay.get(u, id));
    }

    @GetMapping("/rooms/{id}")
    public Mono<Map<String, Object>> room(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(u -> slay.forRoom(u, id));
    }

    @PostMapping("/competitions/{id}/join")
    public Mono<Map<String, Object>> join(
            @PathVariable UUID id, @RequestBody SlayService.Join body) {
        return CurrentUser.id().flatMap(u -> slay.join(u, id, body));
    }

    @PostMapping("/competitions/{id}/start")
    public Mono<Map<String, Object>> start(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(u -> slay.start(u, id));
    }

    @PostMapping("/competitions/{id}/submit")
    public Mono<Map<String, Object>> submit(
            @PathVariable UUID id, @RequestBody SlayService.Submit body) {
        return CurrentUser.id().flatMap(u -> slay.submit(u, id, body.lookId()));
    }

    @PostMapping("/competitions/{id}/judge")
    public Mono<Map<String, Object>> judge(@PathVariable UUID id, @RequestBody Verdict body) {
        return CurrentUser.id().flatMap(u -> slay.judge(u, id, body.entryId(), body.slay()));
    }

    @PostMapping("/competitions/{id}/final-vote")
    public Mono<Map<String, Object>> finalVote(@PathVariable UUID id, @RequestBody Choice body) {
        return CurrentUser.id().flatMap(u -> slay.finalVote(u, id, body.entryId()));
    }

    @PostMapping("/competitions/{id}/cancel")
    public Mono<Map<String, Object>> cancel(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(u -> slay.cancel(u, id));
    }

    @GetMapping("/competitions/{id}/ballot")
    public Mono<SlayService.Ballot> ballot(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(u -> slay.ballot(u, id));
    }

    @PostMapping("/ballots/{id}")
    public Mono<Void> vote(@PathVariable UUID id, @RequestBody Choice body) {
        return CurrentUser.id().flatMap(u -> slay.vote(u, id, body.entryId()));
    }

    @PostMapping("/reports")
    public Mono<Void> report(@RequestBody Report body) {
        return CurrentUser.id().flatMap(u -> slay.report(u, body.lookId(), body.reason()));
    }

    @PostMapping("/blocks")
    public Mono<Void> block(@RequestBody Block body) {
        return CurrentUser.id().flatMap(u -> slay.block(u, body.userId()));
    }
}
