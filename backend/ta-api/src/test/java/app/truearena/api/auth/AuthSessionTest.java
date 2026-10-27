package app.truearena.api.auth;
import app.truearena.api.coins.CoinService;
import app.truearena.persistence.*;
import org.junit.jupiter.api.*;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import reactor.core.publisher.Mono;
import java.time.Instant;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
class AuthSessionTest {
 static UserRow persisted(UserRow u) {
  return new UserRow(java.util.UUID.randomUUID(),u.displayName(),u.avatarUrl(),u.phone(),u.email(),u.username(),u.isGuest(),u.deviceId(),u.isBot(),u.ownerUserId(),u.botGameType(),u.botDifficulty(),u.publicKey(),u.createdAt());
 }
 final UserRepository users=mock(UserRepository.class);
 final OtpService otp=mock(OtpService.class);
 final GoogleAuthService google=mock(GoogleAuthService.class);
 final AppleAuthService apple=mock(AppleAuthService.class);
 final GoogleAccountRepository googleLinks=mock(GoogleAccountRepository.class);
 final AppleAccountRepository appleLinks=mock(AppleAccountRepository.class);
 final UsernameGenerator names=mock(UsernameGenerator.class);
 final CoinService coins=mock(CoinService.class);
 final LoginEventRepository logins=mock(LoginEventRepository.class);
 final JwtService jwt=mock(JwtService.class);
 final AuthController auth=new AuthController(otp,jwt,users,names,google,googleLinks,apple,appleLinks,coins,logins,mock(IssueEventRepository.class));
 final UserRow guest=persisted(UserRow.newGuest("device","Guest","guest_handle"));
 final UserRow account=persisted(UserRow.newUser(null,"a@example.com","Original Name","original_handle"));
 @BeforeEach void setup(){
  when(users.save(any())).thenAnswer(i->Mono.just(i.getArgument(0)));
  when(logins.save(any())).thenAnswer(i->Mono.just(i.getArgument(0)));
  when(users.findById(guest.id())).thenReturn(Mono.just(guest));
  when(users.findByEmail("a@example.com")).thenReturn(Mono.just(account));
  when(otp.verify(anyString(),anyString())).thenReturn(Mono.just(true));
  when(jwt.issueAccess(any())).thenReturn("access");
  when(jwt.issueRefresh(any())).thenReturn("refresh");
 }
 <T>T asGuest(Mono<T> m){return m.contextWrite(ReactiveSecurityContextHolder.withAuthentication(new UsernamePasswordAuthenticationToken(guest.id().toString(),""))).block();}
 void existing(AuthDtos.TokenResponse r){
  assertThat(r.user().id()).isEqualTo(account.id());
  assertThat(r.user().username()).isEqualTo("original_handle");
  assertThat(r.newAccount()).isFalse();
  verify(users,never()).save(any());
 }
 @Test void emailFromGuestRestoresExistingUsername(){existing(asGuest(auth.verifyOtp(new AuthDtos.OtpVerify(null,"a@example.com","123456"))));}
 @Test void appleFromGuestRestoresExistingUsername(){
  when(apple.verify("token","nonce")).thenReturn(Mono.just(new AppleAuthService.AppleIdentity("sub",null)));
  when(appleLinks.findById("sub")).thenReturn(Mono.just(new AppleAccountRow("sub",account.id(),Instant.now())));
  when(users.findById(account.id())).thenReturn(Mono.just(account));
  existing(asGuest(auth.signInWithApple(new AuthDtos.AppleSignInRequest("token","nonce"))));
 }
 @Test void googleFromGuestRestoresExistingUsername(){
  when(google.verify("token")).thenReturn(Mono.just(new GoogleAuthService.GoogleIdentity("sub","a@example.com","Name")));
  when(googleLinks.findById("sub")).thenReturn(Mono.just(new GoogleAccountRow("sub",account.id())));
  when(users.findById(account.id())).thenReturn(Mono.just(account));
  existing(asGuest(auth.signInWithGoogle(new AuthDtos.GoogleSignInRequest("token"))));
 }
 @Test void emailUpgradeKeepsGuestHistoryRequiresSetupAndReleasesDevice(){
  when(users.findByEmail("new@example.com")).thenReturn(Mono.empty());
  var r=asGuest(auth.verifyOtp(new AuthDtos.OtpVerify(null,"new@example.com","123456")));
  assertThat(r.newAccount()).isTrue(); assertThat(r.user().id()).isEqualTo(guest.id());
  verify(users).save(argThat(u->!u.isGuest()&&u.deviceId()==null));
 }
 @Test void firstAppleUpgradeRequiresSetupAndKeepsGuestHistory(){
  when(apple.verify("token","nonce")).thenReturn(Mono.just(new AppleAuthService.AppleIdentity("new-sub","new@example.com")));
  when(appleLinks.findById("new-sub")).thenReturn(Mono.empty());
  when(appleLinks.findByUserId(guest.id())).thenReturn(Mono.empty());
  when(appleLinks.link("new-sub",guest.id())).thenReturn(Mono.just(1));
  when(users.findByEmail("new@example.com")).thenReturn(Mono.empty());
  var r=asGuest(auth.signInWithApple(new AuthDtos.AppleSignInRequest("token","nonce")));
  assertThat(r.newAccount()).isTrue();assertThat(r.user().id()).isEqualTo(guest.id());
  verify(users).save(argThat(u->!u.isGuest()&&u.deviceId()==null));
 }
 @Test void firstGoogleUpgradeRequiresSetupAndKeepsGuestHistory(){
  when(google.verify("token")).thenReturn(Mono.just(new GoogleAuthService.GoogleIdentity("new-sub","new@example.com","New Name")));
  when(googleLinks.findById("new-sub")).thenReturn(Mono.empty());
  when(googleLinks.findByUserId(guest.id())).thenReturn(Mono.empty());
  when(googleLinks.link("new-sub",guest.id())).thenReturn(Mono.just(1));
  when(users.findByEmail("new@example.com")).thenReturn(Mono.empty());
  var r=asGuest(auth.signInWithGoogle(new AuthDtos.GoogleSignInRequest("token")));
  assertThat(r.newAccount()).isTrue();assertThat(r.user().id()).isEqualTo(guest.id());
  verify(users).save(argThat(u->!u.isGuest()&&u.deviceId()==null));
 }
 @Test void phoneFromGuestRestoresExistingAccount(){
  when(users.findByPhone("+441234567890")).thenReturn(Mono.just(account));
  existing(asGuest(auth.verifyOtp(new AuthDtos.OtpVerify("+441234567890",null,"123456"))));
 }
 @Test void guestEndpointStillRecoversActualGuests(){
  when(users.findByDeviceId("device")).thenReturn(Mono.just(guest));
  var r=auth.guestSignIn(new AuthDtos.GuestSignInRequest("device","Another nickname")).block();
  assertThat(r.user().isGuest()).isTrue();assertThat(r.user().id()).isEqualTo(guest.id());
  verify(users,never()).save(any());
 }
 @Test void guestEndpointCannotRecoverRegisteredAccountWithOldDeviceLink(){
  var legacy=new UserRow(account.id(),account.displayName(),null,null,account.email(),account.username(),false,"device",false,null,null,null,null,account.createdAt());
  when(users.findByDeviceId("device")).thenReturn(Mono.just(legacy));
  when(names.resolve(null)).thenReturn(Mono.just("fresh_guest"));
  when(coins.credit(any(),anyLong(),anyString(),any())).thenReturn(Mono.empty());
  var r=auth.guestSignIn(new AuthDtos.GuestSignInRequest("device","New Guest")).block();
  assertThat(r.user().isGuest()).isTrue();assertThat(r.user().id()).isNotEqualTo(account.id());
  verify(users).save(argThat(u->account.id().equals(u.id())&&u.deviceId()==null));
 }
}
