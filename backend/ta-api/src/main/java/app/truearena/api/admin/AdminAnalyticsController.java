package app.truearena.api.admin;

import app.truearena.api.admin.AdminDtos.IssuePage;
import app.truearena.api.admin.AdminDtos.Overview;
import app.truearena.api.admin.AdminDtos.RetentionDay;
import app.truearena.api.admin.AdminDtos.UserDetail;
import app.truearena.api.admin.AdminDtos.UserPage;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirements;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

/**
 * Backs the /notvisible/analytics admin dashboard. Not part of the app's own JWT
 * auth system on purpose — gated instead by {@link AdminKeyFilter} on a static
 * shared secret ({@code ADMIN_API_KEY}), since there's no admin-role concept
 * anywhere in the user model. Never called by the mobile app.
 */
@RestController
@RequestMapping("/api/v1/admin")
@Tag(name = "admin", description = "Internal analytics dashboard — gated by X-Admin-Key, not user auth")
@SecurityRequirements
public class AdminAnalyticsController {

    private final AdminAnalyticsService analytics;

    public AdminAnalyticsController(AdminAnalyticsService analytics) {
        this.analytics = analytics;
    }

    @GetMapping("/overview")
    @Operation(summary = "Global KPIs — DAU/WAU/MAU, retention, coin economy, issue counts")
    public Mono<Overview> overview() {
        return analytics.overview();
    }

    @GetMapping("/users")
    @Operation(summary = "Paginated per-user table")
    public Mono<UserPage> users(@RequestParam(defaultValue = "0") int page,
                                 @RequestParam(defaultValue = "25") int size,
                                 @RequestParam(required = false) String q,
                                 @RequestParam(required = false) String sort) {
        return analytics.users(page, size, q, sort);
    }

    @GetMapping("/users/{id}")
    @Operation(summary = "One user's drill-down: login history, recent games, coin ledger, issues")
    public Mono<UserDetail> userDetail(@PathVariable UUID id) {
        return analytics.userDetail(id);
    }

    @GetMapping("/issues")
    @Operation(summary = "Recent operational issues (currently: failed OTP verification)")
    public Mono<IssuePage> issues(@RequestParam(defaultValue = "0") int page,
                                   @RequestParam(defaultValue = "25") int size,
                                   @RequestParam(required = false) String type) {
        return analytics.issues(page, size, type);
    }

    @GetMapping("/retention")
    @Operation(summary = "Daily signup cohorts with D1/D7 return rate")
    public Flux<RetentionDay> retention(@RequestParam(defaultValue = "30") int days) {
        return analytics.retention(days);
    }
}
