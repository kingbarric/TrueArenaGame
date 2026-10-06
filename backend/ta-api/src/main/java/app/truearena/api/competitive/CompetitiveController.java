package app.truearena.api.competitive;

import app.truearena.api.competitive.CompetitiveDtos.CompetitiveProfileView;
import app.truearena.api.competitive.CompetitiveDtos.CountryView;
import app.truearena.api.competitive.CompetitiveDtos.LeaderboardView;
import app.truearena.api.competitive.CompetitiveDtos.MatchHistoryView;
import app.truearena.api.competitive.CompetitiveDtos.RegionView;
import app.truearena.api.competitive.CompetitiveDtos.UpdateLocationRequest;
import app.truearena.api.support.ApiExceptions;
import app.truearena.api.support.CurrentUser;
import app.truearena.persistence.UserRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.List;

/**
 * Competitive identity, rankings and match history.
 *
 * <p>Read-mostly by design: the only thing a client can write is where they
 * compete. Ratings, ranks, outcomes and achievements are produced server-side
 * from engine-validated games (see {@link RatingService}) — there is no
 * endpoint that accepts any of them.
 */
@RestController
@RequestMapping("/api/v1")
@Tag(name = "competitive")
public class CompetitiveController {

    private final CompetitiveProfileService profiles;
    private final LeaderboardService leaderboards;
    private final CompetitiveSettings settings;
    private final UserRepository users;

    public CompetitiveController(CompetitiveProfileService profiles, LeaderboardService leaderboards,
                                 CompetitiveSettings settings, UserRepository users) {
        this.profiles = profiles;
        this.leaderboards = leaderboards;
        this.settings = settings;
        this.users = users;
    }

    @GetMapping("/me/competitive")
    @Operation(summary = "Your competitive identity: PlayHuud number, founding status, location, per-game ratings and ranks")
    public Mono<CompetitiveProfileView> mine() {
        return CurrentUser.id().flatMap(id -> profiles.profileOf(id, true));
    }

    @PatchMapping("/me/competitive")
    @Operation(summary = "Set where you compete (country / state / optional city). Country and state changes are rate-limited.")
    public Mono<CompetitiveProfileView> updateMine(@Valid @RequestBody UpdateLocationRequest body) {
        return CurrentUser.id().flatMap(id -> profiles.updateLocation(id, body));
    }

    /**
     * Another player's competitive profile. If they've turned their profile
     * off, this still answers — with identity only and {@code restricted} set —
     * so the app can say "private" rather than "not found". Looking yourself
     * up by username always gets the full view.
     */
    @GetMapping("/players/{username}/competitive")
    @Operation(summary = "Another player's competitive profile (identity only if they made it private)")
    public Mono<CompetitiveProfileView> player(@PathVariable String username) {
        return CurrentUser.id().flatMap(viewer -> profiles.profileOfUsername(username, viewer));
    }

    @GetMapping("/me/matches")
    @Operation(summary = "Your match history, ranked and casual, newest first, with rating changes")
    public Mono<List<MatchHistoryView>> myMatches(@RequestParam(required = false) String gameType,
                                                  @RequestParam(defaultValue = "20") int limit) {
        return CurrentUser.id().flatMap(id -> profiles.matchesOf(id, blankToNull(gameType), limit));
    }

    @GetMapping("/players/{username}/matches")
    @Operation(summary = "A player's public match history")
    public Mono<List<MatchHistoryView>> playerMatches(@PathVariable String username,
                                                      @RequestParam(required = false) String gameType,
                                                      @RequestParam(defaultValue = "20") int limit) {
        return Mono.zip(CurrentUser.id(), users.findByUsername(username)
                        .filter(u -> !u.isBot())
                        .switchIfEmpty(Mono.error(ApiExceptions.notFound("player not found"))))
                .flatMap(t -> t.getT1().equals(t.getT2().id())
                        ? profiles.matchesOf(t.getT2().id(), blankToNull(gameType), limit)
                        : profiles.isPublic(t.getT2().id()).flatMap(visible -> visible
                                ? profiles.matchesOf(t.getT2().id(), blankToNull(gameType), limit)
                                : Mono.error(ApiExceptions.forbidden("this player's profile is private"))));
    }

    /**
     * {@code scope}: global | country | region | friends. For country/region,
     * {@code key} picks which board (e.g. {@code NG}, {@code NG-RI}); omitted
     * means the viewer's own.
     */
    @GetMapping("/leaderboards/{gameType}")
    @Operation(summary = "A leaderboard page, with the viewer's own standing pinned")
    public Mono<LeaderboardView> leaderboard(@PathVariable String gameType,
                                             @RequestParam(defaultValue = "global") String scope,
                                             @RequestParam(required = false) String key,
                                             @RequestParam(defaultValue = "25") int limit,
                                             @RequestParam(defaultValue = "0") int offset) {
        if (!settings.isRated(gameType)) {
            return Mono.error(ApiExceptions.notFound("no rankings for " + gameType));
        }
        return CurrentUser.id().flatMap(viewer ->
                leaderboards.page(gameType, LeaderboardScope.parse(scope), key, viewer, limit, offset));
    }

    @GetMapping("/competitive/games")
    @Operation(summary = "Game types that have a skill rating")
    public Mono<List<String>> ratedGames() {
        return Mono.just(settings.ratedGameTypes().stream().sorted().toList());
    }

    @GetMapping("/competitive/locations")
    @Operation(summary = "Countries a player can compete in (ISO 3166-1)")
    public Mono<List<CountryView>> countries() {
        return Mono.just(LocationCatalog.countries().stream()
                .map(c -> new CountryView(c.code(), c.name(), c.catalogued())).toList());
    }

    @GetMapping("/competitive/locations/{countryCode}")
    @Operation(summary = "States / regions for a country. Empty means the country takes a free-text region.")
    public Mono<List<RegionView>> regions(@PathVariable String countryCode) {
        return Mono.just(LocationCatalog.regions(countryCode).stream()
                .map(r -> new RegionView(r.code(), r.name())).toList());
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s;
    }
}
