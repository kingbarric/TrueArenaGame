package app.truearena.api.auth;

import app.truearena.api.auth.AuthDtos.AppleSignInRequest;
import app.truearena.api.coins.CoinService;
import app.truearena.persistence.AppleAccountRepository;
import app.truearena.persistence.AppleAccountRow;
import app.truearena.persistence.GoogleAccountRepository;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.persistence.LoginEventRepository;
import app.truearena.persistence.IssueEventRepository;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AppleSignInTest {
    private final JwtService jwt = mock(JwtService.class);
    private final UserRepository users = mock(UserRepository.class);
    private final AppleAuthService apple = mock(AppleAuthService.class);
    private final AppleAccountRepository links = mock(AppleAccountRepository.class);
    private final LoginEventRepository loginEvents = mock(LoginEventRepository.class);
    private final AuthController controller = new AuthController(
            mock(OtpService.class), jwt, users, mock(UsernameGenerator.class),
            mock(GoogleAuthService.class), mock(GoogleAccountRepository.class),
            apple, links, mock(CoinService.class), loginEvents, mock(IssueEventRepository.class));

    @Test
    void returningAppleUserUsesSubjectWithoutEmail() {
        UUID id = UUID.randomUUID();
        UserRow user = new UserRow(id, "Player", null, null, "old@example.com", "player", false,
                null, false, null, null, null, null, null);
        when(apple.verify("token", "nonce"))
                .thenReturn(Mono.just(new AppleAuthService.AppleIdentity("apple-sub", null)));
        when(links.findById("apple-sub")).thenReturn(Mono.just(new AppleAccountRow("apple-sub", id, null)));
        when(users.findById(id)).thenReturn(Mono.just(user));
        when(jwt.issueAccess(id)).thenReturn("access");
        when(jwt.issueRefresh(id)).thenReturn("refresh");
        when(loginEvents.save(any())).thenReturn(Mono.empty());

        StepVerifier.create(controller.signInWithApple(new AppleSignInRequest("token", "nonce")))
                .assertNext(result -> {
                    assertThat(result.user().id()).isEqualTo(id);
                    assertThat(result.newAccount()).isFalse();
                }).verifyComplete();
        verify(users, never()).findByEmail(any());
    }
}
