package app.truearena.api.competitive;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Arrays;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Tunables for the competitive system, all overridable from config so a
 * threshold can move without a release.
 *
 * <ul>
 *   <li>{@code ratedGameTypes} — which games have a skill rating at all. Adding
 *       Chess is a config change once its module exists; nothing below the
 *       policy is game-specific.</li>
 *   <li>{@code placementGames} — rated games before a player stops being
 *       provisional and can appear on a leaderboard. Stops one lucky win from
 *       producing a credible-looking national #1.</li>
 *   <li>{@code maxRatedGamesPerPairPerDay} — after this many rated games
 *       between the same two accounts in 24h, further games between them are
 *       recorded but unrated. The cheapest effective guard against farming a
 *       secondary account.</li>
 * </ul>
 */
@Component
public class CompetitiveSettings {

    private final Set<String> ratedGameTypes;
    private final int placementGames;
    private final int maxRatedGamesPerPairPerDay;
    private final Duration locationCooldown;
    private final int maxLocationChanges;

    public CompetitiveSettings(
            @Value("${truearena.competitive.rated-game-types:draughts}") String ratedGameTypes,
            @Value("${truearena.competitive.placement-games:10}") int placementGames,
            @Value("${truearena.competitive.max-rated-games-per-pair-per-day:5}") int maxRatedGamesPerPairPerDay,
            @Value("${truearena.competitive.location-cooldown-days:30}") int locationCooldownDays,
            @Value("${truearena.competitive.max-location-changes:3}") int maxLocationChanges) {
        this.ratedGameTypes = Arrays.stream(ratedGameTypes.split(","))
                .map(String::trim).filter(s -> !s.isEmpty()).collect(Collectors.toUnmodifiableSet());
        this.placementGames = placementGames;
        this.maxRatedGamesPerPairPerDay = maxRatedGamesPerPairPerDay;
        this.locationCooldown = Duration.ofDays(locationCooldownDays);
        this.maxLocationChanges = maxLocationChanges;
    }

    /** Defaults, for tests and anywhere a Spring context isn't available. */
    public static CompetitiveSettings defaults() {
        return new CompetitiveSettings("draughts", 10, 5, 30, 3);
    }

    public Set<String> ratedGameTypes() {
        return ratedGameTypes;
    }

    public boolean isRated(String gameType) {
        return ratedGameTypes.contains(gameType);
    }

    public int placementGames() {
        return placementGames;
    }

    public int maxRatedGamesPerPairPerDay() {
        return maxRatedGamesPerPairPerDay;
    }

    public Duration locationCooldown() {
        return locationCooldown;
    }

    public int maxLocationChanges() {
        return maxLocationChanges;
    }
}
