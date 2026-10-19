package app.truearena.api.safety;
import org.junit.jupiter.api.Test;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.web.server.ResponseStatusException;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
class AgeSafetyServiceTest {
    @Test void unknownAndAllMinorBandsFailClosedWhileAdultPasses() {
        var service=new AgeSafetyService(mock(DatabaseClient.class),true);
        assertThat(service.statusOf(null).canAccess()).isFalse();
        for(var band:AgeSafetyService.Band.values()) {
            var status=service.statusOf(new AgeSafetyService.Profile(band,"GB"));
            assertThat(status.canAccess()).isEqualTo(band==AgeSafetyService.Band.ADULT);
            assertThat(status.teenAccessEnabled()).isFalse();
            assertThat(status.minimumAge()).isEqualTo(18);
            assertThat(status.source()).isEqualTo("self_declared");
        }
    }
    @Test void rolloutIsOffByDefaultAndDoesNotQueryTheDatabaseForSessionChecks() {
        var db=mock(DatabaseClient.class); var service=new AgeSafetyService(db,false);
        service.requireAccess(UUID.randomUUID()).block(); verifyNoInteractions(db);
        assertThat(service.statusOf(null).canAccess()).isTrue();
    }
    @Test void recoveryRoutesDoNotAllowProfileEditsOrSocialReads() {
        assertThat(AgeSafetyService.recoveryRoute("GET","/api/v1/me/age-safety")).isTrue();
        assertThat(AgeSafetyService.recoveryRoute("PUT","/api/v1/me/age-safety")).isTrue();
        assertThat(AgeSafetyService.recoveryRoute("DELETE","/api/v1/me/account")).isTrue();
        assertThat(AgeSafetyService.recoveryRoute("POST","/api/v1/players/"+UUID.randomUUID()+"/report")).isTrue();
        for(var path:new String[]{"/api/v1/me/wallet","/api/v1/me/matches","/api/v1/me/age-safety/extra","/api/v1/huud/feed"})
            assertThat(AgeSafetyService.recoveryRoute("GET",path)).isFalse();
        assertThat(AgeSafetyService.recoveryRoute("PATCH","/api/v1/me")).isFalse();
    }
    @Test void invalidDeclarationsNeverWriteAnything() {
        var db=mock(DatabaseClient.class); var service=new AgeSafetyService(db,true);
        for(var d: new AgeSafetyService.Declaration[]{
                new AgeSafetyService.Declaration(null,"GB",true),
                new AgeSafetyService.Declaration(AgeSafetyService.Band.ADULT,"XX",true),
                new AgeSafetyService.Declaration(AgeSafetyService.Band.ADULT,"GB",false)})
            assertThatThrownBy(()->service.declare(UUID.randomUUID(),d).block()).isInstanceOf(ResponseStatusException.class);
        verifyNoInteractions(db);
    }
}
