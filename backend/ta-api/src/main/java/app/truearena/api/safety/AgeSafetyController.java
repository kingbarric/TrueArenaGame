package app.truearena.api.safety;

import app.truearena.api.support.CurrentUser;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api/v1/me/age-safety")
public class AgeSafetyController {
    private final AgeSafetyService safety;
    public AgeSafetyController(AgeSafetyService safety) { this.safety=safety; }
    @GetMapping public Mono<AgeSafetyService.Status> status() {
        return CurrentUser.id().flatMap(safety::status);
    }
    @PutMapping public Mono<AgeSafetyService.Status> declare(@RequestBody AgeSafetyService.Declaration body) {
        return CurrentUser.id().flatMap(user->safety.declare(user,body));
    }
}
