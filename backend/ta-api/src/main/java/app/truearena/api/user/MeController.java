package app.truearena.api.user;

import app.truearena.api.auth.AuthDtos.ProfileUpdateRequest;
import app.truearena.api.auth.AuthDtos.StatsView;
import app.truearena.api.auth.AuthDtos.UserView;
import app.truearena.api.auth.UsernameGenerator;
import app.truearena.api.coins.CoinDtos.TierView;
import app.truearena.api.coins.CoinDtos.WalletTransactionView;
import app.truearena.api.coins.CoinDtos.WalletView;
import app.truearena.api.coins.CoinService;
import app.truearena.api.coins.CoinTier;
import app.truearena.api.support.ApiExceptions;
import app.truearena.api.support.CurrentUser;
import app.truearena.persistence.PlayerStatsRepository;
import app.truearena.persistence.PlayerStatsRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api/v1")
@Tag(name = "user")
public class MeController {

    private final UserRepository users;
    private final PlayerStatsRepository stats;
    private final UsernameGenerator usernames;
    private final CoinService coins;

    public MeController(UserRepository users, PlayerStatsRepository stats, UsernameGenerator usernames, CoinService coins) {
        this.users = users;
        this.stats = stats;
        this.usernames = usernames;
        this.coins = coins;
    }

    @GetMapping("/me")
    @Operation(summary = "The authenticated user")
    public Mono<UserView> me() {
        return currentUser().map(this::view);
    }

    /**
     * Uploads this device's E2E public key (X25519, base64) — called once
     * per fresh keypair (a new install, or the first launch after this
     * shipped). Overwrites any previous key: only ever one public key per
     * account today, so signing in on a new device supersedes the old one
     * for future messages (existing DM threads a peer already encrypted to
     * the old key become undecipherable — see `AppState._ensurePublicKey`,
     * a known v1 limitation of not syncing the private key across devices).
     */
    @PostMapping("/me/public-key")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "Upload this device's E2E public key (X25519, base64)")
    public Mono<Void> setPublicKey(@Valid @RequestBody PublicKeyRequest body) {
        return currentUser().flatMap(u -> users.save(u.withPublicKey(body.publicKey()))).then();
    }

    public record PublicKeyRequest(@NotBlank @Size(max = 200) String publicKey) {
    }

    @PatchMapping("/me")
    @Operation(summary = "Change your username and/or profile icon")
    public Mono<UserView> updateMe(@Valid @RequestBody ProfileUpdateRequest body) {
        return currentUser().flatMap(u -> {
            Mono<String> nextUsername = body.username() == null || body.username().isBlank()
                    ? Mono.just(u.username())
                    : (body.username().equals(u.username()) ? Mono.just(u.username()) : usernames.resolve(body.username()));
            return nextUsername.flatMap(username -> users.save(u.withProfile(username, body.avatarEmoji())));
        }).map(this::view);
    }

    @GetMapping("/me/stats")
    @Operation(summary = "Lifetime games played / win rate for the authenticated user")
    public Mono<StatsView> myStats() {
        return CurrentUser.id()
                .flatMap(stats::findByUserIdAndGroupIdIsNull)
                .map(this::view)
                .defaultIfEmpty(new StatsView(0, 0, 0, 0));
    }

    @GetMapping("/me/wallet")
    @Operation(summary = "Coin balance and recent transaction history for the authenticated user")
    public Mono<WalletView> myWallet(@RequestParam(defaultValue = "20") int limit) {
        return CurrentUser.id().flatMap(uid -> Mono.zip(coins.balance(uid), coins.lifetimeCoins(uid))
                .flatMap(balanceAndLifetime -> coins.history(uid, limit)
                        .map(t -> new WalletTransactionView(t.delta(), t.balanceAfter(), t.reason(), t.createdAt()))
                        .collectList()
                        .map(history -> {
                            long lifetime = balanceAndLifetime.getT2();
                            TierView tier = TierView.of(CoinTier.forLifetimeCoins(lifetime), lifetime);
                            return new WalletView(balanceAndLifetime.getT1(), tier, history);
                        })));
    }

    private Mono<UserRow> currentUser() {
        return CurrentUser.id()
                .flatMap(users::findById)
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("unknown user")));
    }

    private UserView view(UserRow u) {
        return new UserView(u.id(), u.displayName(), u.username(), u.phone(), u.email(), u.avatarUrl(), u.isGuest());
    }

    private StatsView view(PlayerStatsRow r) {
        return new StatsView(r.gamesPlayed(), r.wins(), r.traitorGames(), r.traitorWins());
    }
}
