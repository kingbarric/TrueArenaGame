package app.truearena.api.huudspace;

import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.voice.LiveKitProperties;
import app.truearena.voice.LiveKitTokenService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;
import java.util.Base64;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class HuudPreviewServiceTest {
    final HuudSpaceService huuds = mock(HuudSpaceService.class);
    final UserRepository users = mock(UserRepository.class);
    final LiveKitTokenService tokens = new LiveKitTokenService(new LiveKitProperties(
            "wss://voice.example.test", "test-key", "test-secret-not-used-outside-this-test-123456789", null));
    final HuudPreviewService previews = new HuudPreviewService(huuds, users, tokens);
    final UUID user = UUID.randomUUID(), id = UUID.randomUUID();

    @Test void forbiddenPreviewNeverMintsOrLooksUpAnIdentity() {
        when(huuds.watch(user, id)).thenReturn(Mono.error(ApiExceptions.forbidden("not allowed")));
        StepVerifier.create(previews.listen(user, id)).expectError().verify();
        verifyNoInteractions(users);
    }

    @Test void tokenIsShortLivedReceiveOnlyAndSeparateForEveryVisit() throws Exception {
        var view = mock(HuudSpaceDtos.HuudSpaceView.class);
        when(view.live()).thenReturn(true);
        when(view.voiceRoom()).thenReturn("huud-" + id);
        when(huuds.watch(user, id)).thenReturn(Mono.just(view));
        var row = mock(UserRow.class);
        when(row.username()).thenReturn("ava");
        when(users.findById(user)).thenReturn(Mono.just(row));
        var first = previews.listen(user, id).block();
        var second = previews.listen(user, id).block();
        assertThat(first.previewId()).isNotEqualTo(second.previewId());
        var payload = new ObjectMapper().readTree(Base64.getUrlDecoder().decode(first.token().split("\\.")[1]));
        assertThat(payload.get("sub").asText()).isEqualTo(HuudSpaceService.previewIdentity(user, first.previewId()));
        assertThat(payload.get("video").get("room").asText()).isEqualTo("huud-" + id);
        assertThat(payload.get("video").get("roomJoin").asBoolean()).isTrue();
        assertThat(payload.get("video").get("canSubscribe").asBoolean()).isTrue();
        assertThat(payload.get("video").get("canPublish").asBoolean()).isFalse();
        assertThat(payload.get("video").get("canPublishData").asBoolean()).isFalse();
        assertThat(payload.get("exp").asLong() - java.time.Instant.now().getEpochSecond()).isBetween(59L, 61L);
    }
}
