package app.truearena.api.auth;

import app.truearena.api.coins.CoinService;
import app.truearena.api.auth.AuthDtos.GoogleSignInRequest;
import app.truearena.api.auth.AuthDtos.AppleChallenge;
import app.truearena.api.auth.AuthDtos.AppleSignInRequest;
import app.truearena.api.auth.AuthDtos.GuestSignInRequest;
import app.truearena.api.auth.AuthDtos.OtpRequest;
import app.truearena.api.auth.AuthDtos.OtpVerify;
import app.truearena.api.auth.AuthDtos.RefreshRequest;
import app.truearena.api.auth.AuthDtos.TokenResponse;
import app.truearena.api.auth.AuthDtos.UserView;
import app.truearena.api.support.ApiExceptions;
import app.truearena.api.support.CurrentUser;
import app.truearena.persistence.UserRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.GoogleAccountRepository;
import app.truearena.persistence.AppleAccountRepository;
import app.truearena.persistence.LoginEventRepository;
import app.truearena.persistence.LoginEventRow;
import app.truearena.persistence.IssueEventRepository;
import app.truearena.persistence.IssueEventRow;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirements;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/auth")
@Tag(name = "auth", description = "Phone or email + OTP. In the local profile, code 000000 always verifies.")
@SecurityRequirements // no bearer needed on these
public class AuthController {

    private final OtpService otp;
    private final JwtService jwt;
    private final UserRepository users;
    private final UsernameGenerator usernames;
    private final GoogleAuthService google;
    private final GoogleAccountRepository googleAccounts;
    private final AppleAuthService apple;
    private final AppleAccountRepository appleAccounts;
    private final CoinService coins;
    private final LoginEventRepository loginEvents;
    private final IssueEventRepository issueEvents;

    public AuthController(OtpService otp, JwtService jwt, UserRepository users, UsernameGenerator usernames,
                          GoogleAuthService google, GoogleAccountRepository googleAccounts,
                          AppleAuthService apple, AppleAccountRepository appleAccounts, CoinService coins,
                          LoginEventRepository loginEvents, IssueEventRepository issueEvents) {
        this.coins = coins;
        this.otp = otp;
        this.jwt = jwt;
        this.users = users;
        this.usernames = usernames;
        this.google = google;
        this.googleAccounts = googleAccounts;
        this.apple = apple;
        this.appleAccounts = appleAccounts;
        this.loginEvents = loginEvents;
        this.issueEvents = issueEvents;
    }

    @PostMapping("/otp/request")
    @ResponseStatus(HttpStatus.ACCEPTED)
    @Operation(summary = "Send an OTP code by email, or use the local phone stub")
    public Mono<Void> requestOtp(@Valid @RequestBody OtpRequest body) {
        boolean hasPhone = body.phone() != null && !body.phone().isBlank();
        boolean hasEmail = body.email() != null && !body.email().isBlank();
        if (hasPhone == hasEmail) { // neither, or both — exactly one is required
            return Mono.error(ApiExceptions.badRequest("provide exactly one of phone or email"));
        }
        return hasPhone ? otp.requestPhone(body.phone()) : otp.requestEmail(body.email());
    }

    @PostMapping("/otp/verify")
    @Operation(summary = "Verify an OTP; creates the account (or upgrades the caller's guest "
            + "account in place, if the request carries a guest's bearer token) and returns JWTs")
    public Mono<TokenResponse> verifyOtp(@Valid @RequestBody OtpVerify body) {
        boolean hasPhone = body.phone() != null && !body.phone().isBlank();
        boolean hasEmail = body.email() != null && !body.email().isBlank();
        if (hasPhone == hasEmail) {
            return Mono.error(ApiExceptions.badRequest("provide exactly one of phone or email"));
        }
        String phone = hasPhone ? body.phone() : null;
        String email = hasEmail ? body.email() : null;
        String identifier = hasPhone ? body.phone() : body.email();
        String method = hasPhone ? "phone" : "email";
        return otp.verify(identifier, body.code())
                .flatMap(ok -> {
                    if (!ok) {
                        return recordIssue(null, "OTP_FAILED", method)
                                .then(Mono.error(ApiExceptions.unauthorized("invalid or expired code")));
                    }
                    // A guest calling this with their own guest bearer token upgrades that
                    // same account in place (same id, same room membership/stats) instead of
                    // finding-or-creating a separate one — see UserRow.upgraded. Anyone else
                    // (no token, or already a real account re-verifying) keeps today's path.
                    return CurrentUser.id()
                            .flatMap(users::findById)
                            .filter(UserRow::isGuest)
                            .flatMap(guest -> upgradeGuest(guest, phone, email))
                            .flatMap(u -> recordLogin(u, method))
                            .map(u -> tokensFor(u, false))
                            .switchIfEmpty(Mono.defer(() -> upsertUser(phone, email, null)
                                    .flatMap(r -> recordLogin(r.user(), method).map(u -> new Upserted(u, r.created())))
                                    .map(r -> tokensFor(r.user(), r.created()))));
                });
    }

    @PostMapping("/guest")
    @Operation(summary = "Real (server-known) guest identity, keyed by device id — lets a device "
            + "create/join rooms before signing up. The same device reconnecting reuses the same "
            + "guest row and rooms rather than minting a new identity every time.")
    public Mono<TokenResponse> guestSignIn(@Valid @RequestBody GuestSignInRequest body) {
        return users.findByDeviceId(body.deviceId())
                .switchIfEmpty(Mono.defer(() -> {
                    String name = body.displayName() != null && !body.displayName().isBlank()
                            ? body.displayName() : "Player";
                    return usernames.resolve(null)
                            .flatMap(username -> users.save(UserRow.newGuest(body.deviceId(), name, username)))
                            .flatMap(this::grantWelcomeCoins);
                }))
                .flatMap(u -> recordLogin(u, "guest"))
                .map(u -> tokensFor(u, false));
    }

    @PostMapping("/google")
    @Operation(summary = "Sign in with a Google ID token (see docs/DEV_REFERENCE.md for the Cloud Console setup this needs)")
    public Mono<TokenResponse> signInWithGoogle(@Valid @RequestBody GoogleSignInRequest body) {
        return google.verify(body.idToken())
                .flatMap(identity -> googleAccounts.findById(identity.subject())
                        .flatMap(link -> users.findById(link.userId())
                                .map(user -> new Upserted(user, false)))
                        .switchIfEmpty(Mono.defer(() -> registerGoogle(identity))))
                .flatMap(r -> recordLogin(r.user(), "google").map(u -> new Upserted(u, r.created())))
                .map(r -> tokensFor(r.user(), r.created()));
    }

    private Mono<Upserted> registerGoogle(GoogleAuthService.GoogleIdentity identity) {
        return users.findByEmail(identity.email())
                .map(user -> new Upserted(user, false))
                .switchIfEmpty(Mono.defer(() -> CurrentUser.id()
                        .flatMap(users::findById)
                        .filter(UserRow::isGuest)
                        .flatMap(guest -> users.save(guest.upgraded(null, identity.email()))
                                .map(user -> new Upserted(user, false)))
                        .switchIfEmpty(Mono.defer(() -> upsertUser(null, identity.email(), identity.name())))))
                .flatMap(result -> googleAccounts.findByUserId(result.user().id())
                        .flatMap(link -> Mono.<Upserted>error(ApiExceptions.conflict(
                                "this account is linked to another Google account")))
                        .switchIfEmpty(Mono.defer(() -> googleAccounts.link(
                                identity.subject(), result.user().id())).thenReturn(result)));
    }

    @PostMapping("/apple/challenge")
    @Operation(summary = "Start a short-lived Sign in with Apple challenge")
    public Mono<AppleChallenge> appleChallenge() {
        return apple.challenge().map(AppleChallenge::new);
    }

    @PostMapping("/apple")
    @Operation(summary = "Sign in with a verified native iOS Apple identity token")
    public Mono<TokenResponse> signInWithApple(@Valid @RequestBody AppleSignInRequest body) {
        return apple.verify(body.idToken(), body.nonce())
                .flatMap(identity -> appleAccounts.findById(identity.subject())
                        .flatMap(link -> users.findById(link.userId())
                                .map(user -> new Upserted(user, false)))
                        .switchIfEmpty(Mono.defer(() -> registerApple(identity))))
                .flatMap(r -> recordLogin(r.user(), "apple").map(u -> new Upserted(u, r.created())))
                .map(r -> tokensFor(r.user(), r.created()));
    }

    private Mono<Upserted> registerApple(AppleAuthService.AppleIdentity identity) {
        String email = identity.email();
        Mono<Upserted> existingEmail = email == null ? Mono.empty()
                : users.findByEmail(email).map(user -> new Upserted(user, false));
        return existingEmail
                .switchIfEmpty(Mono.defer(() -> {
                    if (email == null) {
                        return Mono.error(ApiExceptions.unauthorized("Apple did not provide an email for this new account"));
                    }
                    return CurrentUser.id()
                            .flatMap(users::findById)
                            .filter(UserRow::isGuest)
                            .flatMap(guest -> users.save(guest.upgraded(null, email))
                                    .map(user -> new Upserted(user, false)))
                            .switchIfEmpty(Mono.defer(() -> upsertUser(null, email, null)));
                }))
                .flatMap(result -> appleAccounts.findByUserId(result.user().id())
                        .flatMap(link -> Mono.<Upserted>error(ApiExceptions.conflict(
                                "this account is linked to another Apple account")))
                        .switchIfEmpty(Mono.defer(() -> appleAccounts.link(
                                identity.subject(), result.user().id()).thenReturn(result))));
    }

    @PostMapping("/refresh")
    @Operation(summary = "Exchange a refresh token for a fresh pair")
    public Mono<TokenResponse> refresh(@Valid @RequestBody RefreshRequest body) {
        return Mono.fromCallable(() -> jwt.parseRefresh(body.refreshToken()))
                .onErrorMap(e -> ApiExceptions.unauthorized("invalid refresh token"))
                .flatMap(users::findById)
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("unknown user")))
                .flatMap(u -> recordLogin(u, "refresh"))
                .map(u -> tokensFor(u, false));
    }

    /** Best-effort: a login-tracking write must never fail or block a sign-in. */
    private Mono<UserRow> recordLogin(UserRow u, String method) {
        return loginEvents.save(LoginEventRow.of(u.id(), method)).thenReturn(u).onErrorReturn(u);
    }

    /** Best-effort: an issue-tracking write must never fail or block the caller's response. */
    private Mono<Void> recordIssue(UUID userId, String type, String detail) {
        return issueEvents.save(IssueEventRow.of(userId, type, detail)).then().onErrorResume(e -> Mono.empty());
    }

    /** Attaches a verified phone/email to a guest's own row — same id, same room
     * membership and stats. If that contact method is already claimed by a
     * different (real) account, fails with a conflict rather than silently
     * merging two identities together. */
    private Mono<UserRow> upgradeGuest(UserRow guest, String phone, String email) {
        Mono<UserRow> clash = phone != null ? users.findByPhone(phone) : users.findByEmail(email);
        return clash
                .flatMap(existing -> existing.id().equals(guest.id())
                        ? Mono.<UserRow>empty()
                        : Mono.error(ApiExceptions.conflict("that " + (phone != null ? "phone" : "email") + " is already in use")))
                .switchIfEmpty(Mono.defer(() -> users.save(guest.upgraded(phone, email))));
    }

    private record Upserted(UserRow user, boolean created) {
    }

    private Mono<Upserted> upsertUser(String phone, String email, String googleName) {
        Mono<UserRow> existing = phone != null ? users.findByPhone(phone) : users.findByEmail(email);
        return existing.map(u -> new Upserted(u, false)).switchIfEmpty(Mono.defer(() -> {
            String fallback = phone != null
                    ? "Player " + phone.substring(Math.max(0, phone.length() - 4))
                    : "Player " + email.substring(0, Math.min(4, email.indexOf('@') < 0 ? email.length() : email.indexOf('@')));
            String name = googleName != null && !googleName.isBlank() ? googleName : fallback;
            return usernames.resolve(null)
                    .flatMap(username -> users.save(UserRow.newUser(phone, email, name, username)))
                    .flatMap(this::grantWelcomeCoins)
                    .map(u -> new Upserted(u, true));
        }));
    }

    /**
     * Seeds a brand-new account with {@link CoinService#WELCOME_GRANT} for
     * staked play. The ledger keeps the grant traceable; failure never blocks
     * signup.
     */
    private Mono<UserRow> grantWelcomeCoins(UserRow u) {
        return coins.credit(u.id(), CoinService.WELCOME_GRANT, CoinService.REASON_WELCOME, null)
                .thenReturn(u)
                .onErrorReturn(u);
    }

    private TokenResponse tokensFor(UserRow u, boolean newAccount) {
        return new TokenResponse(
                jwt.issueAccess(u.id()),
                jwt.issueRefresh(u.id()),
                jwt.accessTtlSeconds(),
                new UserView(u.id(), u.displayName(), u.username(), u.phone(), u.email(), u.avatarUrl(), u.isGuest()),
                newAccount);
    }
}
