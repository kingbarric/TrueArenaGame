package app.truearena.api.competitive;

import app.truearena.api.competitive.LocationChangePolicy.Allowed;
import app.truearena.api.competitive.LocationChangePolicy.Rejected;
import app.truearena.api.competitive.LocationChangePolicy.Unchanged;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class LocationChangePolicyTest {

    private final LocationChangePolicy policy = new LocationChangePolicy(CompetitiveSettings.defaults());
    private final Instant now = Instant.parse("2026-10-06T12:00:00Z");

    @Test
    @DisplayName("setting a location for the first time is free and starts no cooldown")
    void firstSet() {
        assertThat(policy.decide(null, null, 0, null, "NG", "NG-RI", now))
                .isEqualTo(new Allowed(0, null));
    }

    @Test
    @DisplayName("adding a state to an existing country is completing the profile, not moving")
    void completingRegion() {
        assertThat(policy.decide("NG", null, 0, null, "NG", "NG-LA", now))
                .isEqualTo(new Allowed(0, null));
    }

    @Test
    @DisplayName("re-submitting the same location is a no-op")
    void unchanged() {
        assertThat(policy.decide("NG", "NG-RI", 2, null, "NG", "NG-RI", now)).isInstanceOf(Unchanged.class);
    }

    @Test
    @DisplayName("the first correction is immediate but starts the cooldown")
    void firstCorrection() {
        assertThat(policy.decide("NG", "NG-RI", 0, null, "NG", "NG-LA", now))
                .isEqualTo(new Allowed(1, now.plus(Duration.ofDays(30))));
    }

    @Test
    @DisplayName("a second change inside the cooldown is refused with the retry date")
    void cooldownEnforced() {
        Instant lockedUntil = now.plus(Duration.ofDays(10));
        var decision = policy.decide("NG", "NG-LA", 1, lockedUntil, "GH", "GH-AA", now);
        assertThat(decision).isInstanceOf(Rejected.class);
        assertThat(((Rejected) decision).retryAt()).isEqualTo(lockedUntil);
    }

    @Test
    @DisplayName("after the cooldown, a change is allowed and restarts it")
    void afterCooldown() {
        assertThat(policy.decide("NG", "NG-LA", 1, now.minusSeconds(1), "NG", "NG-OY", now))
                .isEqualTo(new Allowed(2, now.plus(Duration.ofDays(30))));
    }

    @Test
    @DisplayName("past the change limit, only support can move you")
    void supportRequired() {
        var decision = policy.decide("NG", "NG-LA", 3, null, "NG", "NG-OY", now);
        assertThat(decision).isInstanceOf(Rejected.class);
        assertThat(((Rejected) decision).retryAt()).isNull();
    }
}
