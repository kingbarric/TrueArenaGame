package app.truearena.api.huudspace;

import app.truearena.api.support.CurrentUser;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api/v1/championships/invite")
public class ChampionshipInvitationController {
    private final ChampionshipInvitationService invitations;
    public ChampionshipInvitationController(ChampionshipInvitationService invitations) { this.invitations = invitations; }
    @PostMapping("/{code}/accept")
    public Mono<ChampionshipInvitationService.Accepted> accept(@PathVariable String code) {
        return CurrentUser.id().flatMap(user -> invitations.accept(code, user));
    }
}
