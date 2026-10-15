package app.truearena.api.huudspace;

import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.UserRepository;
import app.truearena.voice.LiveKitTokenService;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import java.util.UUID;

/** A separate receive-only connection; previewing never grants a live seat or mic. */
@Service
public class HuudPreviewService {
    private final HuudSpaceService huuds;
    private final UserRepository users;
    private final LiveKitTokenService tokens;

    public HuudPreviewService(HuudSpaceService huuds, UserRepository users, LiveKitTokenService tokens) {
        this.huuds = huuds;
        this.users = users;
        this.tokens = tokens;
    }

    public record ListenToken(String roomName, String token, String livekitUrl, UUID previewId) {}

    public Mono<ListenToken> listen(UUID user, UUID id) {
        return huuds.watch(user, id).filter(HuudSpaceDtos.HuudSpaceView::live)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("This Huud is no longer live")))
                .flatMap(huud -> users.findById(user)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such user")))
                .map(self -> {
                    UUID preview = UUID.randomUUID();
                    return new ListenToken(huud.voiceRoom(),
                            tokens.mintPreviewToken(huud.voiceRoom(), HuudSpaceService.previewIdentity(user, preview),
                                    self.username() == null ? self.displayName() : self.username()), tokens.wsUrl(), preview);
                }));
    }
}
