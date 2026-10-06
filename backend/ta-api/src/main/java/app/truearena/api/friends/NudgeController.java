package app.truearena.api.friends;

import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/friends")
@Tag(name = "friends")
public class NudgeController {

    private final NudgeService nudges;

    public NudgeController(NudgeService nudges) {
        this.nudges = nudges;
    }

    /** Buzz a friend's phone to ask them to come online. */
    @PostMapping("/{friendUserId}/nudge")
    public Mono<Void> nudge(@PathVariable UUID friendUserId) {
        return CurrentUser.id().flatMap(uid -> nudges.nudge(uid, friendUserId));
    }
}
