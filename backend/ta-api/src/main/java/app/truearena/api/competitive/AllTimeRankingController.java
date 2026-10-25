package app.truearena.api.competitive;

import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.UUID;

/**
 * All-time rankings — the top 20 on PlayHuud for each game, and overall.
 * Ranked by the same confidence-adjusted /100 score the cards show.
 * Ten qualifying games are required for a public place.
 */
@RestController
@RequestMapping("/api/v1/rankings")
public class AllTimeRankingController {

    static final int TOP = 20;

    private final StrengthService strength;

    public AllTimeRankingController(StrengthService strength) {
        this.strength = strength;
    }

    public record RankedPlayer(int rank, UUID userId, String username, String displayName, String avatarUrl,
                               long strength, long gamesPlayed, long wins, long draws, long losses) {
    }

    /** {@code you}: your own place, even outside the top 20 (null if you haven't played). */
    public record AllTimeRankingView(String gameType, List<RankedPlayer> top, RankedPlayer you) {
    }

    @GetMapping("/all-time")
    @Operation(summary = "All-time top 20 by strength — one game (gameType) or overall (no gameType)")
    public Mono<AllTimeRankingView> allTime(@RequestParam(required = false) String gameType) {
        return CurrentUser.id().flatMap(me -> ranking(gameType, me));
    }

    public Mono<AllTimeRankingView> ranking(String gameType, UUID me) {
        String game = gameType == null || gameType.isBlank() ? null : gameType;
        return Mono.zip(top(game), you(game, me).map(java.util.Optional::of).defaultIfEmpty(java.util.Optional.empty()))
                .map(t -> new AllTimeRankingView(game, t.getT1(), t.getT2().orElse(null)));
    }

    private Mono<List<RankedPlayer>> top(String game) {
        return strength.top(game).map(rows -> rows.stream().map(AllTimeRankingController::row).toList());
    }
    private Mono<RankedPlayer> you(String game, UUID me) {
        return strength.own(game, me).map(AllTimeRankingController::row);
    }
    private static RankedPlayer row(StrengthService.Entry r) {
        return new RankedPlayer(r.global() == null ? 0 : r.global(), r.userId(), r.username(), r.displayName(), r.avatarUrl(),
                r.score(), r.games(), r.wins(), r.draws(), r.losses());
    }
}
