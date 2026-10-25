package app.truearena.api.invitation;
import app.truearena.api.championship.ChampionshipService;
import app.truearena.api.huudspace.HuudSpaceService;
import app.truearena.api.huudspace.HuudSpaceDtos.InvitePreview;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import java.time.Instant;
import java.util.UUID;
import static org.mockito.Mockito.*;
import static org.assertj.core.api.Assertions.assertThat;

class InvitationPageControllerTest {
    @Test void championshipMetadataHasBothBrandAndGameWithoutLeakingTheBracket() throws Exception {
        var cups = mock(ChampionshipService.class); var huuds = mock(HuudSpaceService.class);
        var controller = new InvitationPageController(cups, huuds, "", "");
        when(cups.publicInvitation("ABCD2345")).thenReturn(Mono.just(new ChampionshipService.Invitation(UUID.randomUUID(),
                "ABCD2345", "<script>attack</script> & Friday", "chess", 8, "private", Instant.now(), "lobby", 2)));
        var response = controller.championship("ABCD2345").block();
        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody()).contains("og:title", "invite-chess.png", "Play as a guest", "&lt;script&gt;attack&lt;/script&gt; &amp; Friday")
                .doesNotContain("<script>attack</script>", "{{", "participants", "winnerId");
        assertThat(controller.stores()).containsEntry("ios", "").containsEntry("android", "");
    }
    @Test void huudInvitesShareTheSameAppOnlyGuestFlow() throws Exception {
        var cups = mock(ChampionshipService.class); var huuds = mock(HuudSpaceService.class);
        var controller = new InvitationPageController(cups, huuds, "", "");
        when(huuds.invitePreview("ABC234")).thenReturn(Mono.just(new InvitePreview("ABC234", "Weekend crew", "host", true, 3)));
        var html = controller.huud("ABC234").block().getBody();
        assertThat(html).contains("Weekend crew", "playhuud:///huud/ABC234", "invite-huud.png", "Games are played in the PlayHuud app");
    }
    @Test void storeDestinationsAreActualHttpsStoreLinksAndMissingListingsRemainUnavailable() throws Exception {
        assertThat(InvitationPageController.storeUrl("https://evil.example/store", "apps.apple.com")).isEmpty();
        assertThat(InvitationPageController.storeUrl("javascript:alert(1)", "apps.apple.com")).isEmpty();
        assertThat(InvitationPageController.storeUrl("https://apps.apple.com/app/id123456789", "apps.apple.com")).contains("id123456789");
        var controller = new InvitationPageController(mock(ChampionshipService.class), mock(HuudSpaceService.class), "", "");
        assertThat(controller.huud("invalid").block().getStatusCode().value()).isEqualTo(404);
    }    @Test void aTemporaryBackendOutageDoesNotClaimTheInvitationHasExpired() throws Exception {
        var huuds = mock(HuudSpaceService.class);
        when(huuds.invitePreview("ABC234")).thenReturn(Mono.error(new IllegalStateException("private database details")));
        var page = new InvitationPageController(mock(ChampionshipService.class), huuds, "", "").huud("ABC234").block();
        assertThat(page.getStatusCode().value()).isEqualTo(503);
        assertThat(page.getBody()).contains("temporarily unavailable").doesNotContain("private database details");
    }

}
