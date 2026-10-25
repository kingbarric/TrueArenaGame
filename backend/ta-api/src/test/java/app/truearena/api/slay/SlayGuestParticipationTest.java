package app.truearena.api.slay;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.ReactiveTransactionManager;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;
import java.util.UUID;
import static org.mockito.Mockito.*;

class SlayGuestParticipationTest {
    @Test void aHumanGuestMayParticipateButCannotHostAndAnAgentCannotParticipate() {
        var users = mock(UserRepository.class);
        var service = new SlayService(null, new ObjectMapper(), null, users, null, null, null, mock(ReactiveTransactionManager.class));
        var guest = UUID.randomUUID(); var bot = UUID.randomUUID();
        when(users.findById(guest)).thenReturn(Mono.just(new UserRow(guest, "Guest", null, null, null, "guest", true, "device", false, null, null, null, null, null)));
        when(users.findById(bot)).thenReturn(Mono.just(new UserRow(bot, "Cyber", null, null, null, "cyber", false, null, true, null, "slayhuud", "hard", null, null)));
        StepVerifier.create(service.humanPlayer(guest)).verifyComplete();
        StepVerifier.create(service.humanPlayer(bot)).expectError(ResponseStatusException.class).verify();
        StepVerifier.create(service.create(guest, new SlayService.Create("battle", "night-out", 2, "female", false)))
                .expectError(ResponseStatusException.class).verify();
    }
}
