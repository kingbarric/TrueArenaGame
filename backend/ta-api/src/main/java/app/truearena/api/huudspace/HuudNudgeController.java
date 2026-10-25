package app.truearena.api.huudspace;

import app.truearena.api.support.CurrentUser;
import java.util.UUID;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api/v1/huud-spaces")
public class HuudNudgeController {
    private final HuudNudgeService nudges;
    public HuudNudgeController(HuudNudgeService nudges) { this.nudges=nudges; }
    @PostMapping("/{id}/members/{target}/nudge")
    public Mono<Void> nudge(@PathVariable UUID id,@PathVariable UUID target) {
        return CurrentUser.id().flatMap(user -> nudges.nudge(user,id,target));
    }
}
