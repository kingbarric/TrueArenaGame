package app.truearena.api.competitive;

import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.UUID;

/**
 * All-time rankings — the top 20 on PlayHuud for each game, and overall.
 * Ranked by strength, which every finished game adds to (+20 a win, +8 a
 * draw, +3 a loss — the same as the shield), so every game counts, not just
 * the rated ones. Agents and guests aren't ranked.
 */
@RestController
@RequestMapping("/api/v1/rankings")
public class AllTimeRankingController {

    static final int WIN = 20;
    static final int DRAW = 8;
    static final int LOSS = 3;
    static final int TOP = 20;

    private final DatabaseClient db;

    public AllTimeRankingController(DatabaseClient db) {
        this.db = db;
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

    /** Each player's totals — for one game, or summed over all of them. */
    private String totals(String game) {
        return "SELECT s.user_id, sum(s.games_played) AS games, sum(s.wins) AS wins, sum(s.draws) AS draws, "
                + "sum(s.losses) AS losses, sum(s.wins * " + WIN + " + s.draws * " + DRAW + " + s.losses * " + LOSS
                + ") AS strength "
                + "FROM player_game_stats s JOIN users u ON u.id = s.user_id "
                + "WHERE NOT u.is_bot AND NOT u.is_guest AND s.games_played > 0 "
                + (game == null ? "" : "AND s.game_type = :g ")
                + "GROUP BY s.user_id";
    }

    private static final String RANKED = "SELECT t.*, u.username, u.display_name, u.avatar_url, "
            + "rank() OVER (ORDER BY t.strength DESC, t.wins DESC, t.games ASC) AS place "
            + "FROM (%s) t JOIN users u ON u.id = t.user_id";

    private Mono<List<RankedPlayer>> top(String game) {
        var spec = db.sql(String.format(RANKED, totals(game)) + " ORDER BY place, u.username LIMIT " + TOP);
        if (game != null) spec = spec.bind("g", game);
        return spec.map((r, m) -> row(r)).all().collectList();
    }

    private Mono<RankedPlayer> you(String game, UUID me) {
        var spec = db.sql("SELECT * FROM (" + String.format(RANKED, totals(game)) + ") ranked WHERE user_id = :me")
                .bind("me", me);
        if (game != null) spec = spec.bind("g", game);
        return spec.map((r, m) -> row(r)).one();
    }

    private static RankedPlayer row(io.r2dbc.spi.Row r) {
        return new RankedPlayer(num(r.get("place")).intValue(), r.get("user_id", UUID.class),
                r.get("username", String.class), r.get("display_name", String.class), r.get("avatar_url", String.class),
                num(r.get("strength")).longValue(), num(r.get("games")).longValue(), num(r.get("wins")).longValue(),
                num(r.get("draws")).longValue(), num(r.get("losses")).longValue());
    }

    private static Number num(Object value) {
        return value instanceof Number n ? n : 0;
    }
}
