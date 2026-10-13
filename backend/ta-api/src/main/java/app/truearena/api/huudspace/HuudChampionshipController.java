package app.truearena.api.huudspace;

import app.truearena.api.huudspace.HuudSpaceDtos.ChampionshipRequest;
import app.truearena.api.huudspace.HuudSpaceDtos.HuudChampionship;
import app.truearena.api.huudspace.HuudSpaceDtos.HuudSpaceView;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/huud-spaces/{id}/championship")
@Tag(name = "Huud championships", description = "A Chess or Draughts knockout inside a Huud")
public class HuudChampionshipController {

    private final HuudChampionshipService championships;

    public HuudChampionshipController(HuudChampionshipService championships) {
        this.championships = championships;
    }

    @GetMapping
    @Operation(summary = "The Huud's championship: registration, bracket, live matches, result")
    public Mono<HuudChampionship> get(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> championships.view(id, user));
    }

    @PostMapping
    @Operation(summary = "Host only, while Live: open registration for a championship")
    public Mono<HuudChampionship> create(@PathVariable UUID id, @Valid @RequestBody ChampionshipRequest body) {
        return CurrentUser.id().flatMap(user -> championships.create(user, id, body));
    }

    @DeleteMapping
    @Operation(summary = "Host only: call off registration, or put a finished bracket away — back to hanging out")
    public Mono<HuudSpaceView> close(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> championships.close(user, id));
    }

    @PostMapping("/start")
    @Operation(summary = "Host only: start before the set time with whoever has registered — at least four")
    public Mono<HuudChampionship> start(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> championships.startNow(user, id));
    }

    @PostMapping("/register")
    @Operation(summary = "Take a place; once the start time has come, the last place locks registration and starts the draw")
    public Mono<HuudChampionship> register(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> championships.register(user, id));
    }

    @DeleteMapping("/register")
    @Operation(summary = "Give your place back while registration is open")
    public Mono<HuudChampionship> withdraw(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> championships.withdraw(user, id));
    }

    @DeleteMapping("/players/{userId}")
    @Operation(summary = "Host only, while registration is open: free someone's place")
    public Mono<HuudChampionship> removePlayer(@PathVariable UUID id, @PathVariable UUID userId) {
        return CurrentUser.id().flatMap(user -> championships.removePlayer(user, id, userId));
    }

    @PostMapping("/matches/{matchId}/end-both-absent")
    @Operation(summary = "Host only: end a pairing with no winner once both players are gone past their allowance")
    public Mono<HuudChampionship> endBothAbsent(@PathVariable UUID id, @PathVariable UUID matchId) {
        return CurrentUser.id().flatMap(user -> championships.endBothAbsent(user, id, matchId));
    }
}
