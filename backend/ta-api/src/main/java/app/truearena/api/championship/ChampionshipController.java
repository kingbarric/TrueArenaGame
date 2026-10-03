package app.truearena.api.championship;

import app.truearena.api.support.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/championships")
public class ChampionshipController {
    private final ChampionshipService service;

    public ChampionshipController(ChampionshipService service) { this.service = service; }

    public record Create(@NotBlank String name, int size, @NotBlank String visibility,
                         @NotNull Instant scheduledAt) {}

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<ChampionshipService.View> create(@Valid @RequestBody Create request) {
        return CurrentUser.id().flatMap(u -> service.create(u, request.name(), request.size(),
                request.visibility(), request.scheduledAt()));
    }

    @GetMapping("/discover")
    public Flux<ChampionshipService.View> discover() {
        return CurrentUser.id().flatMapMany(service::discover);
    }

    @GetMapping("/mine")
    public Flux<ChampionshipService.View> mine() {
        return CurrentUser.id().flatMapMany(service::mine);
    }

    @GetMapping("/badges/mine")
    public Flux<ChampionshipService.Badge> badges() {
        return CurrentUser.id().flatMapMany(service::badges);
    }

    @GetMapping("/invite/{code}")
    public Mono<ChampionshipService.View> invite(@PathVariable String code) {
        return CurrentUser.id().flatMap(u -> service.invitation(code, u));
    }

    @GetMapping("/invite/{code}/preview")
    public Mono<ChampionshipService.Invitation> publicInvitePreview(@PathVariable String code) {
        return service.publicInvitation(code);
    }

    @GetMapping("/{id}")
    public Mono<ChampionshipService.View> one(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(u -> service.detail(id, u));
    }

    @PostMapping("/{id}/join")
    public Mono<ChampionshipService.View> join(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(u -> service.join(id, u));
    }

    @PostMapping("/{id}/start")
    public Mono<ChampionshipService.View> start(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(u -> service.startNow(id, u));
    }

    @PostMapping("/matches/{matchId}/end-both-absent")
    public Mono<Void> endBothAbsent(@PathVariable UUID matchId) {
        return CurrentUser.id().flatMap(u -> service.endBothAbsent(matchId, u));
    }
}
