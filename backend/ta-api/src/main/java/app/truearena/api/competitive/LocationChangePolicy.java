package app.truearena.api.competitive;

import java.time.Instant;
import java.util.Objects;

/**
 * Stops location switching from being a way into an easier leaderboard, without
 * punishing a genuine typo or a genuine move.
 *
 * <ul>
 *   <li>Setting a location for the first time is free.</li>
 *   <li>Adding a region to a country you already have is free — that's
 *       completing the profile, not moving.</li>
 *   <li>The first real change (a correction) is allowed immediately, then
 *       starts a cooldown.</li>
 *   <li>Each later change needs the cooldown to have elapsed, and restarts it.</li>
 *   <li>Past {@code maxLocationChanges}, further changes need support review.</li>
 * </ul>
 *
 * Every change is counted and timestamped on the profile so a reviewer can see
 * the pattern afterwards. City never goes through here: it doesn't decide any
 * leaderboard membership.
 */
public final class LocationChangePolicy {

    public sealed interface Decision permits Unchanged, Allowed, Rejected {
    }

    /** The request matches what's already stored. */
    public record Unchanged() implements Decision {
    }

    public record Allowed(int locationChanges, Instant lockedUntil) implements Decision {
    }

    /** {@code retryAt} null means "contact support", not "wait". */
    public record Rejected(String message, Instant retryAt) implements Decision {
    }

    private final CompetitiveSettings settings;

    public LocationChangePolicy(CompetitiveSettings settings) {
        this.settings = settings;
    }

    public Decision decide(String currentCountry, String currentRegion, int changesSoFar, Instant lockedUntil,
                           String newCountry, String newRegion, Instant now) {
        if (Objects.equals(currentCountry, newCountry) && Objects.equals(currentRegion, newRegion)) {
            return new Unchanged();
        }
        boolean firstSet = currentCountry == null;
        boolean completingRegion = Objects.equals(currentCountry, newCountry) && currentRegion == null;
        if (firstSet || completingRegion) {
            return new Allowed(changesSoFar, lockedUntil);
        }
        if (changesSoFar >= settings.maxLocationChanges()) {
            return new Rejected("Your location has already been changed " + changesSoFar
                    + " times. Contact support to change it again.", null);
        }
        if (changesSoFar > 0 && lockedUntil != null && now.isBefore(lockedUntil)) {
            return new Rejected("You can change your ranking location again after this date.", lockedUntil);
        }
        return new Allowed(changesSoFar + 1, now.plus(settings.locationCooldown()));
    }
}
