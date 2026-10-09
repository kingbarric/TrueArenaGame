package app.truearena.api.safety;

import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/players")
@Tag(name = "Safety", description = "Block and report")
public class SafetyController {

    public record ReportRequest(@NotBlank String reason, @Size(max = 300) String details, UUID huudSpaceId,
                                Long messageId, UUID postId, Boolean block) {
    }

    private final SafetyService safety;

    public SafetyController(SafetyService safety) {
        this.safety = safety;
    }

    @PostMapping("/{id}/block")
    @Operation(summary = "Block a player: no Huuds together, no chat from them, no friendship")
    public Mono<Void> block(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(me -> safety.block(me, id));
    }

    @DeleteMapping("/{id}/block")
    public Mono<Void> unblock(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(me -> safety.unblock(me, id));
    }

    @GetMapping("/blocked")
    public Flux<SafetyService.BlockedPlayer> blocked() {
        return CurrentUser.id().flatMapMany(safety::blocked);
    }

    @PostMapping("/{id}/report")
    @Operation(summary = "Report a player to the PlayHuud team; block too with block=true")
    public Mono<Void> report(@PathVariable UUID id, @Valid @RequestBody ReportRequest body) {
        return CurrentUser.id().flatMap(me -> safety.report(me, id, body.reason(), body.details(), body.huudSpaceId(),
                body.messageId(), body.postId(), Boolean.TRUE.equals(body.block())));
    }
}
