package app.truearena.api.auth;

import app.truearena.api.auth.AuthDtos.OtpRequest;
import app.truearena.api.auth.AuthDtos.OtpVerify;
import app.truearena.api.auth.AuthDtos.RefreshRequest;
import app.truearena.api.auth.AuthDtos.TokenResponse;
import app.truearena.api.auth.AuthDtos.UserView;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.UserRow;
import app.truearena.persistence.UserRepository;
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

@RestController
@RequestMapping("/api/v1/auth")
@Tag(name = "auth", description = "Phone + OTP. In the local profile, code 000000 always verifies.")
@SecurityRequirements // no bearer needed on these
public class AuthController {

    private final OtpService otp;
    private final JwtService jwt;
    private final UserRepository users;

    public AuthController(OtpService otp, JwtService jwt, UserRepository users) {
        this.otp = otp;
        this.jwt = jwt;
        this.users = users;
    }

    @PostMapping("/otp/request")
    @ResponseStatus(HttpStatus.ACCEPTED)
    @Operation(summary = "Send an OTP code to a phone number (logged to the console by the dev SMS stub)")
    public Mono<Void> requestOtp(@Valid @RequestBody OtpRequest body) {
        return otp.request(body.phone());
    }

    @PostMapping("/otp/verify")
    @Operation(summary = "Verify an OTP; creates the account on first use and returns JWTs")
    public Mono<TokenResponse> verifyOtp(@Valid @RequestBody OtpVerify body) {
        return otp.verify(body.phone(), body.code())
                .flatMap(ok -> ok
                        ? upsertUser(body.phone()).map(this::tokensFor)
                        : Mono.error(ApiExceptions.unauthorized("invalid or expired code")));
    }

    @PostMapping("/refresh")
    @Operation(summary = "Exchange a refresh token for a fresh pair")
    public Mono<TokenResponse> refresh(@Valid @RequestBody RefreshRequest body) {
        return Mono.fromCallable(() -> jwt.parseRefresh(body.refreshToken()))
                .onErrorMap(e -> ApiExceptions.unauthorized("invalid refresh token"))
                .flatMap(users::findById)
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("unknown user")))
                .map(this::tokensFor);
    }

    private Mono<UserRow> upsertUser(String phone) {
        String last4 = phone.length() >= 4 ? phone.substring(phone.length() - 4) : phone;
        return users.findByPhone(phone)
                .switchIfEmpty(users.save(UserRow.newUser(phone, "Player " + last4)));
    }

    private TokenResponse tokensFor(UserRow u) {
        return new TokenResponse(
                jwt.issueAccess(u.id()),
                jwt.issueRefresh(u.id()),
                jwt.accessTtlSeconds(),
                new UserView(u.id(), u.displayName(), u.phone()));
    }
}
