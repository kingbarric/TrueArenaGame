package app.truearena.api.huudspace;

import app.truearena.api.huudspace.HuudPreviewService.ListenToken;
import app.truearena.api.support.CurrentUser;
import java.util.UUID;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api/v1/huud-spaces")
public class HuudPreviewController {
    private final HuudPreviewService previews;
    private final HuudSpaceService huuds;
    public HuudPreviewController(HuudPreviewService previews, HuudSpaceService huuds) {
        this.previews = previews;
        this.huuds = huuds;
    }
    @PostMapping("/{id}/listen")
    public Mono<ListenToken> listen(@PathVariable UUID id) {
        return CurrentUser.id().flatMap(user -> previews.listen(user, id));
    }
    @DeleteMapping("/{id}/listen/{previewId}")
    public Mono<Void> unwatch(@PathVariable UUID id, @PathVariable UUID previewId) {
        return CurrentUser.id().flatMap(user -> huuds.stopPreview(user, id, previewId));
    }
}
