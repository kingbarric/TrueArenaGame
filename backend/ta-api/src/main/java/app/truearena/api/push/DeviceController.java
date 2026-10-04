package app.truearena.api.push;

import app.truearena.api.push.PushDtos.RegisterDeviceTokenRequest;
import app.truearena.api.push.PushDtos.UnregisterDeviceTokenRequest;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api/v1/devices")
@Tag(name = "push")
public class DeviceController {

    private final PushNotificationService push;

    public DeviceController(PushNotificationService push) {
        this.push = push;
    }

    @PostMapping("/token")
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Register (or re-assign) this device's push token for the signed-in user")
    public Mono<Void> register(@Valid @RequestBody RegisterDeviceTokenRequest body) {
        return CurrentUser.id().flatMap(uid -> push.registerToken(uid, body.platform(), body.token()));
    }

    @DeleteMapping("/token")
    @Operation(summary = "Stop sending push to this token — called on sign-out")
    public Mono<Void> unregister(@Valid @RequestBody UnregisterDeviceTokenRequest body) {
        return CurrentUser.id().flatMap(uid -> push.unregisterToken(uid, body.token()));
    }
}
