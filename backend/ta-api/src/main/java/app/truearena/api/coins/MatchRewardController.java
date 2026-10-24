package app.truearena.api.coins;
import app.truearena.api.support.CurrentUser;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;
import java.util.UUID;
@RestController
@RequestMapping("/api/v1/rooms")
public class MatchRewardController {
    private final MatchRewardService rewards;
    public MatchRewardController(MatchRewardService rewards) { this.rewards=rewards; }
    @GetMapping("/{roomId}/coin-reward")
    public Mono<MatchRewardService.Reward> reward(@PathVariable UUID roomId) {
        return CurrentUser.id().flatMap(id->rewards.forRoom(roomId,id));
    }
}
