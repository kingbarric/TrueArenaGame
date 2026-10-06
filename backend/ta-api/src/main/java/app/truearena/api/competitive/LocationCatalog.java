package app.truearena.api.competitive;

import java.text.Normalizer;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

/**
 * Stable location identifiers, so a leaderboard key can never fork on spelling
 * ("Rivers", "Rivers State", "rivers st." are all {@code NG-RI}).
 *
 * <p>Countries are every ISO 3166-1 alpha-2 code the JDK knows. Regions are
 * ISO 3166-2 codes for the countries listed in {@link #REGIONS}; elsewhere a
 * region is accepted as free text and keyed by a normalised slug
 * ({@code KE-NAIROBI}) — weaker than a catalogue, but it lets a player outside
 * the catalogued countries still unlock regional rankings today. Adding a
 * country's regions here upgrades it with no schema change.
 *
 * <p>Served to the app ({@code GET /competitive/locations}) so there is one
 * list, not a server copy and a client copy.
 */
public final class LocationCatalog {

    public record Country(String code, String name, boolean catalogued) {
    }

    public record Region(String code, String name) {
    }

    private static final Map<String, List<Region>> REGIONS = new LinkedHashMap<>();

    static {
        REGIONS.put("NG", regions(
                "NG-AB", "Abia", "NG-AD", "Adamawa", "NG-AK", "Akwa Ibom", "NG-AN", "Anambra",
                "NG-BA", "Bauchi", "NG-BY", "Bayelsa", "NG-BE", "Benue", "NG-BO", "Borno",
                "NG-CR", "Cross River", "NG-DE", "Delta", "NG-EB", "Ebonyi", "NG-ED", "Edo",
                "NG-EK", "Ekiti", "NG-EN", "Enugu", "NG-FC", "Federal Capital Territory", "NG-GO", "Gombe",
                "NG-IM", "Imo", "NG-JI", "Jigawa", "NG-KD", "Kaduna", "NG-KN", "Kano",
                "NG-KT", "Katsina", "NG-KE", "Kebbi", "NG-KO", "Kogi", "NG-KW", "Kwara",
                "NG-LA", "Lagos", "NG-NA", "Nasarawa", "NG-NI", "Niger", "NG-OG", "Ogun",
                "NG-ON", "Ondo", "NG-OS", "Osun", "NG-OY", "Oyo", "NG-PL", "Plateau",
                "NG-RI", "Rivers", "NG-SO", "Sokoto", "NG-TA", "Taraba", "NG-YO", "Yobe",
                "NG-ZA", "Zamfara"));
        REGIONS.put("GH", regions(
                "GH-AF", "Ahafo", "GH-AH", "Ashanti", "GH-BO", "Bono", "GH-BE", "Bono East",
                "GH-CP", "Central", "GH-EP", "Eastern", "GH-AA", "Greater Accra", "GH-NE", "North East",
                "GH-NP", "Northern", "GH-OT", "Oti", "GH-SV", "Savannah", "GH-UE", "Upper East",
                "GH-UW", "Upper West", "GH-TV", "Volta", "GH-WP", "Western", "GH-WN", "Western North"));
        REGIONS.put("ZA", regions(
                "ZA-EC", "Eastern Cape", "ZA-FS", "Free State", "ZA-GP", "Gauteng", "ZA-KZN", "KwaZulu-Natal",
                "ZA-LP", "Limpopo", "ZA-MP", "Mpumalanga", "ZA-NC", "Northern Cape", "ZA-NW", "North West",
                "ZA-WC", "Western Cape"));
        REGIONS.put("GB", regions(
                "GB-ENG", "England", "GB-NIR", "Northern Ireland", "GB-SCT", "Scotland", "GB-WLS", "Wales"));
        REGIONS.put("US", regions(
                "US-AL", "Alabama", "US-AK", "Alaska", "US-AZ", "Arizona", "US-AR", "Arkansas",
                "US-CA", "California", "US-CO", "Colorado", "US-CT", "Connecticut", "US-DE", "Delaware",
                "US-DC", "District of Columbia", "US-FL", "Florida", "US-GA", "Georgia", "US-HI", "Hawaii",
                "US-ID", "Idaho", "US-IL", "Illinois", "US-IN", "Indiana", "US-IA", "Iowa",
                "US-KS", "Kansas", "US-KY", "Kentucky", "US-LA", "Louisiana", "US-ME", "Maine",
                "US-MD", "Maryland", "US-MA", "Massachusetts", "US-MI", "Michigan", "US-MN", "Minnesota",
                "US-MS", "Mississippi", "US-MO", "Missouri", "US-MT", "Montana", "US-NE", "Nebraska",
                "US-NV", "Nevada", "US-NH", "New Hampshire", "US-NJ", "New Jersey", "US-NM", "New Mexico",
                "US-NY", "New York", "US-NC", "North Carolina", "US-ND", "North Dakota", "US-OH", "Ohio",
                "US-OK", "Oklahoma", "US-OR", "Oregon", "US-PA", "Pennsylvania", "US-RI", "Rhode Island",
                "US-SC", "South Carolina", "US-SD", "South Dakota", "US-TN", "Tennessee", "US-TX", "Texas",
                "US-UT", "Utah", "US-VT", "Vermont", "US-VA", "Virginia", "US-WA", "Washington",
                "US-WV", "West Virginia", "US-WI", "Wisconsin", "US-WY", "Wyoming"));
    }

    private static final List<Country> COUNTRIES = java.util.Arrays.stream(Locale.getISOCountries())
            .map(code -> new Country(code, Locale.of("", code).getDisplayCountry(Locale.ENGLISH),
                    REGIONS.containsKey(code)))
            .sorted(Comparator.comparing(Country::name))
            .toList();

    private LocationCatalog() {
    }

    public static List<Country> countries() {
        return COUNTRIES;
    }

    public static Optional<Country> country(String code) {
        if (code == null) return Optional.empty();
        String upper = code.trim().toUpperCase(Locale.ROOT);
        return COUNTRIES.stream().filter(c -> c.code().equals(upper)).findFirst();
    }

    /** The catalogued regions for a country; empty when that country takes free-text regions. */
    public static List<Region> regions(String countryCode) {
        return countryCode == null ? List.of() : REGIONS.getOrDefault(countryCode.toUpperCase(Locale.ROOT), List.of());
    }

    /**
     * Resolves a player's region choice to a stable identifier. For a catalogued
     * country only a catalogued code is accepted (so nobody can invent
     * "Lagos Island" to get a board of one); for any other country the name is
     * normalised into a slug.
     */
    public static Optional<Region> resolveRegion(String countryCode, String regionCode, String regionName) {
        List<Region> catalogued = regions(countryCode);
        if (!catalogued.isEmpty()) {
            if (regionCode == null) return Optional.empty();
            String wanted = regionCode.trim().toUpperCase(Locale.ROOT);
            return catalogued.stream().filter(r -> r.code().equals(wanted)).findFirst();
        }
        String name = regionName == null ? null : regionName.trim().replaceAll("\\s+", " ");
        if (name == null || name.length() < 2 || name.length() > 60) return Optional.empty();
        String slug = Normalizer.normalize(name, Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "")
                .toUpperCase(Locale.ROOT)
                .replaceAll("[^A-Z0-9]+", "-")
                .replaceAll("(^-|-$)", "");
        if (slug.isEmpty()) return Optional.empty();
        return Optional.of(new Region(countryCode.toUpperCase(Locale.ROOT) + "-" + slug, name));
    }

    private static List<Region> regions(String... codesAndNames) {
        List<Region> list = new java.util.ArrayList<>();
        for (int i = 0; i < codesAndNames.length; i += 2) {
            list.add(new Region(codesAndNames[i], codesAndNames[i + 1]));
        }
        list.sort(Comparator.comparing(Region::name));
        return List.copyOf(list);
    }
}
