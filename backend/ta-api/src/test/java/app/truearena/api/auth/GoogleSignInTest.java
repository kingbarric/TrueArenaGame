package app.truearena.api.auth;

import app.truearena.api.auth.AuthDtos.GoogleSignInRequest;
import app.truearena.api.coins.CoinService;
import app.truearena.persistence.GoogleAccountRepository;
import app.truearena.persistence.GoogleAccountRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class GoogleSignInTest {
    private final OtpService otp = mock(OtpService.class);
    private final JwtService jwt = mock(JwtService.class);
    private final UserRepository users = mock(UserRepository.class);
    private final UsernameGenerator usernames = mock(UsernameGenerator.class);
    private final GoogleAuthService google = mock(GoogleAuthService.class);
    private final GoogleAccountRepository links = mock(GoogleAccountRepository.class);
    private final CoinService coins = mock(CoinService.class);
    private final AuthController controller = new AuthController(otp, jwt, users, usernames, google, links, coins);

    private void token(String subject, String email) {
        when(google.verify("token")).thenReturn(Mono.just(new GoogleAuthService.GoogleIdentity(subject, email, "Google Name")));
        when(jwt.issueAccess(any(UUID.class))).thenReturn("access");
        when(jwt.issueRefresh(any(UUID.class))).thenReturn("refresh");
    }

    @Test
    void returningGoogleUserUsesSubjectEvenIfEmailChanged() {
        UUID id = UUID.randomUUID();
        UserRow user = UserRow.newUser(null, "old@example.com", "Player", "player");
        user = new UserRow(id, user.displayName(), null, null, user.email(), user.username(), false,
                null, false, null, null, null, null, null);
        token("subject-1", "new@example.com");
        when(links.findById("subject-1")).thenReturn(Mono.just(new GoogleAccountRow("subject-1", id)));
        when(users.findById(id)).thenReturn(Mono.just(user));

        StepVerifier.create(controller.signInWithGoogle(new GoogleSignInRequest("token")))
                .assertNext(result -> {
                    assertThat(result.user().id()).isEqualTo(id);
                    assertThat(result.newAccount()).isFalse();
                }).verifyComplete();
        verify(users, never()).findByEmail(anyString());
    }

    @Test
    void firstGoogleSignInUpgradesCurrentGuestWithoutLosingItsId() {
        UUID id = UUID.randomUUID();
        UserRow guest = new UserRow(id, "Guest", null, null, null, "guest", true,
                "device", false, null, null, null, null, null);
        token("subject-2", "guest@example.com");
        when(links.findById("subject-2")).thenReturn(Mono.empty());
        when(users.findByEmail("guest@example.com")).thenReturn(Mono.empty());
        when(users.findById(id)).thenReturn(Mono.just(guest));
        when(users.save(any(UserRow.class))).thenAnswer(inv -> Mono.just(inv.getArgument(0)));
        when(links.findByUserId(id)).thenReturn(Mono.empty());
        when(links.link("subject-2", id)).thenReturn(Mono.just(1));

        var auth = new UsernamePasswordAuthenticationToken(id.toString(), null);
        StepVerifier.create(controller.signInWithGoogle(new GoogleSignInRequest("token"))
                        .contextWrite(ReactiveSecurityContextHolder.withAuthentication(auth)))
                .assertNext(result -> {
                    assertThat(result.user().id()).isEqualTo(id);
                    assertThat(result.user().email()).isEqualTo("guest@example.com");
                    assertThat(result.user().isGuest()).isFalse();
                    assertThat(result.newAccount()).isFalse();
                }).verifyComplete();
        verify(links).link("subject-2", id);
    }

    @Test
    void newGoogleUserIsRegisteredAndLinked() {
        UUID id = UUID.randomUUID();
        token("subject-3", "new@example.com");
        when(links.findById("subject-3")).thenReturn(Mono.empty());
        when(users.findByEmail("new@example.com")).thenReturn(Mono.empty());
        when(usernames.resolve(null)).thenReturn(Mono.just("new_user"));
        when(users.save(any(UserRow.class))).thenAnswer(inv -> {
            UserRow row = inv.getArgument(0);
            return Mono.just(new UserRow(id, row.displayName(), null, null, row.email(), row.username(),
                    false, null, false, null, null, null, null, null));
        });
        when(coins.credit(eq(id), anyLong(), anyString(), eq(null))).thenReturn(Mono.just(100L));
        when(links.findByUserId(id)).thenReturn(Mono.empty());
        when(links.link("subject-3", id)).thenReturn(Mono.just(1));

        StepVerifier.create(controller.signInWithGoogle(new GoogleSignInRequest("token")))
                .assertNext(result -> {
                    assertThat(result.user().id()).isEqualTo(id);
                    assertThat(result.newAccount()).isTrue();
                }).verifyComplete();
        verify(links).link("subject-3", id);
    }

    @Test
    void differentGoogleSubjectCannotClaimAnAlreadyLinkedEmail() {
        UUID id = UUID.randomUUID();
        UserRow user = new UserRow(id, "Player", null, null, "player@example.com", "player",
                false, null, false, null, null, null, null, null);
        token("another-subject", "player@example.com");
        when(links.findById("another-subject")).thenReturn(Mono.empty());
        when(users.findByEmail("player@example.com")).thenReturn(Mono.just(user));
        when(links.findByUserId(id)).thenReturn(Mono.just(new GoogleAccountRow("original-subject", id)));

        StepVerifier.create(controller.signInWithGoogle(new GoogleSignInRequest("token")))
                .expectErrorMatches(error -> error instanceof ResponseStatusException response
                        && response.getStatusCode().value() == 409)
                .verify();
        verify(links, never()).link(anyString(), any(UUID.class));
    }
}
