package app.truearena.api.safety;

import app.truearena.api.support.ApiExceptions;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import java.util.Locale;
import java.util.List;
import java.util.Comparator;
import java.util.Set;
import java.util.UUID;

/** Age declarations are private, immutable, and never treated as verified identity. */
@Service
public class AgeSafetyService {
    public static final String NOTICE_VERSION = "2026-10-19";
    private static final Set<String> COUNTRIES = Set.of(Locale.getISOCountries());
    public enum Band { UNDER_13, AGE_13_15, AGE_16_17, ADULT }
    public record Declaration(Band ageBand, String countryCode, boolean noticeAcknowledged) {}
    public record Profile(Band ageBand, String countryCode) {}
    public record Country(String code,String name) {}
    private static final List<Country> COUNTRY_OPTIONS=COUNTRIES.stream()
            .map(c -> new Country(c,Locale.forLanguageTag("und-"+c).getDisplayCountry(Locale.ENGLISH)))
            .sorted(Comparator.comparing(Country::name)).toList();
    public record Status(boolean enforced, boolean declarationRequired, boolean canAccess,
                         int minimumAge, String ageBand, String countryCode, String source,
                         String noticeVersion, String restriction, boolean teenAccessEnabled, List<Country> countries) {}
    private final DatabaseClient db;
    private final boolean enforced;

    public AgeSafetyService(DatabaseClient db,
            @Value("${truearena.safety.age-enforcement-enabled:false}") boolean enforced) {
        this.db = db; this.enforced = enforced;
    }
    public Mono<Status> status(UUID user) {
        return profile(user).map(this::statusOf).defaultIfEmpty(statusOf(null));
    }
    Mono<Profile> profile(UUID user) {
        return db.sql("SELECT age_band,country_code FROM age_safety_profiles WHERE user_id=:u")
                .bind("u",user).map((r,m)->new Profile(Band.valueOf(r.get("age_band",String.class)),
                        r.get("country_code",String.class).strip())).one();
    }
    Status statusOf(Profile p) {
        // A deliberate launch interlock: do not admit teens until communication,
        // discoverability, age assurance, consent and regional reviews are complete.
        String restriction = p == null ? "AGE_DECLARATION_REQUIRED"
                : p.ageBand() == Band.UNDER_13 ? "BELOW_MINIMUM_AGE"
                : p.ageBand() != Band.ADULT ? "TEEN_ACCESS_NOT_ENABLED" : null;
        return new Status(enforced,p==null,!enforced || restriction==null,18,
                p==null?null:p.ageBand().name(),p==null?null:p.countryCode(),
                p==null?null:"self_declared",NOTICE_VERSION,restriction,false,COUNTRY_OPTIONS);
    }
    public Mono<Status> declare(UUID user, Declaration d) {
        if(d==null || d.ageBand()==null || !d.noticeAcknowledged())
            return Mono.error(ApiExceptions.badRequest("Choose an age range and acknowledge the privacy notice"));
        String country=d.countryCode()==null?"":d.countryCode().strip().toUpperCase(Locale.ROOT);
        if(!COUNTRIES.contains(country)) return Mono.error(ApiExceptions.badRequest("Choose a valid country code"));
        return db.sql("INSERT INTO age_safety_profiles(user_id,age_band,country_code,notice_version) "
                        + "VALUES(:u,:b,:c,:v) ON CONFLICT(user_id) DO NOTHING")
                .bind("u",user).bind("b",d.ageBand().name()).bind("c",country).bind("v",NOTICE_VERSION)
                .fetch().rowsUpdated().then(profile(user))
                .flatMap(p -> p.ageBand()!=d.ageBand() || !p.countryCode().equals(country)
                        ? Mono.error(ApiExceptions.conflict("Age details are already saved. Contact support to request a correction"))
                        : Mono.just(statusOf(p)));
    }
    public Mono<Void> requireAccess(UUID user) {
        if(!enforced) return Mono.empty();
        return status(user).flatMap(s -> s.canAccess()?Mono.empty():
                Mono.error(ApiExceptions.forbidden(s.restriction())));
    }
    /** Exact exceptions: broad /me/** or /safety/** exceptions would expose social data. */
    public static boolean recoveryRoute(String method,String path) {
        return (path.equals("/api/v1/me/age-safety") && (method.equals("GET") || method.equals("PUT")))
                || (method.equals("GET") && (path.equals("/api/v1/me")
                    || path.equals("/api/v1/me/account/deletion-requirements")))
                || (method.equals("DELETE") && path.equals("/api/v1/me/account"))
                || (method.equals("GET") && path.equals("/api/v1/players/blocked"))
                || (method.equals("POST") && path.matches("/api/v1/players/[0-9a-fA-F-]{36}/(report|block)"));
    }
}
