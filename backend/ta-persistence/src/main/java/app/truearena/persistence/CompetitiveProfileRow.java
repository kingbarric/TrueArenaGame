package app.truearena.persistence;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * Where a player competes. Location decides leaderboard MEMBERSHIP only — the
 * player's skill rating is per game ({@link PlayerGameRatingRow}), and the
 * global/country/region ranks are three views of that same number.
 *
 * <p>{@code countryCode} is ISO 3166-1 alpha-2 and {@code regionCode} an ISO
 * 3166-2 style slug, so a leaderboard key can't fork on spelling. The change
 * counters exist so location switching to farm an easier board is both limited
 * (see {@code CompetitiveProfileService}) and visible to a reviewer afterwards.
 */
@Table("competitive_profiles")
public record CompetitiveProfileRow(
        @Id UUID id,
        @Column("user_id") UUID userId,
        @Column("country_code") String countryCode,
        @Column("country_name") String countryName,
        @Column("region_code") String regionCode,
        @Column("region_name") String regionName,
        String city,
        @Column("city_public") boolean cityPublic,
        /** Others can open this player's competitive profile. Public by default. */
        @Column("profile_public") boolean profilePublic,
        @Column("location_changes") int locationChanges,
        @Column("location_updated_at") Instant locationUpdatedAt,
        @Column("location_locked_until") Instant locationLockedUntil,
        @Column("created_at") Instant createdAt,
        @Column("updated_at") Instant updatedAt
) {
    public static CompetitiveProfileRow empty(UUID userId) {
        return new CompetitiveProfileRow(null, userId, null, null, null, null, null, false, true, 0,
                null, null, null, null);
    }

    public boolean hasCountry() {
        return countryCode != null;
    }

    public boolean hasRegion() {
        return regionCode != null;
    }

    public CompetitiveProfileRow withLocation(String newCountryCode, String newCountryName,
                                              String newRegionCode, String newRegionName,
                                              int newChanges, Instant changedAt, Instant lockedUntil) {
        return new CompetitiveProfileRow(id, userId, newCountryCode, newCountryName, newRegionCode, newRegionName,
                city, cityPublic, profilePublic, newChanges, changedAt, lockedUntil, createdAt, Instant.now());
    }

    public CompetitiveProfileRow withCity(String newCity, boolean newCityPublic) {
        return new CompetitiveProfileRow(id, userId, countryCode, countryName, regionCode, regionName,
                newCity, newCityPublic, profilePublic, locationChanges, locationUpdatedAt, locationLockedUntil,
                createdAt, Instant.now());
    }

    public CompetitiveProfileRow withProfilePublic(boolean visible) {
        return new CompetitiveProfileRow(id, userId, countryCode, countryName, regionCode, regionName,
                city, cityPublic, visible, locationChanges, locationUpdatedAt, locationLockedUntil,
                createdAt, Instant.now());
    }
}
