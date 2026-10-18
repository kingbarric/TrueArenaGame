package app.truearena.api.auth;

import app.truearena.api.support.CurrentUser;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api/v1/me/account")
public class AccountDeletionController {
    private final AccountDeletionService deletion;
    public AccountDeletionController(AccountDeletionService deletion) { this.deletion=deletion; }

    @GetMapping("/deletion-requirements")
    public Mono<AccountDeletionService.Requirements> requirements() {
        return CurrentUser.id().flatMap(deletion::requirements);
    }

    @DeleteMapping
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> delete(@RequestBody AccountDeletionService.Confirmation confirmation) {
        // There is deliberately no user ID parameter: a player can erase only self.
        return CurrentUser.id().flatMap(user -> deletion.delete(user,confirmation));
    }
}
