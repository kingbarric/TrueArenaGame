package app.truearena.api.huudspace;

import app.truearena.api.support.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api/v1/me/huud-avatar")
public class HuudAvatarController {
    public record Selection(@NotBlank @Size(max=32) String avatarId, @NotBlank @Size(max=32) String outfitId) {}
    private final HuudAvatarService avatars;
    public HuudAvatarController(HuudAvatarService avatars) { this.avatars=avatars; }
    @GetMapping
    public Mono<HuudAvatarService.Profile> get() { return CurrentUser.id().flatMap(avatars::get); }
    @PatchMapping
    public Mono<HuudAvatarService.Profile> save(@Valid @RequestBody Selection choice) {
        return CurrentUser.id().flatMap(user -> avatars.save(user,choice.avatarId(),choice.outfitId()));
    }
}
