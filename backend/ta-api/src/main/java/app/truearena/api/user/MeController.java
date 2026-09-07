package app.truearena.api.user;

import app.truearena.api.auth.AuthDtos.UserView;
import app.truearena.api.support.ApiExceptions;
import app.truearena.api.support.CurrentUser;
import app.truearena.persistence.UserRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api/v1")
@Tag(name = "user")
public class MeController {

    private final UserRepository users;

    public MeController(UserRepository users) {
        this.users = users;
    }

    @GetMapping("/me")
    @Operation(summary = "The authenticated user")
    public Mono<UserView> me() {
        return CurrentUser.id()
                .flatMap(users::findById)
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("unknown user")))
                .map(u -> new UserView(u.id(), u.displayName(), u.phone()));
    }
}
