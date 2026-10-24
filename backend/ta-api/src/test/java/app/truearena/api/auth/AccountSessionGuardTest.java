package app.truearena.api.auth;

import app.truearena.persistence.UserRepository;
import app.truearena.api.safety.AgeSafetyService;
import org.springframework.r2dbc.core.DatabaseClient;
import app.truearena.persistence.UserRow;
import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.socket.WebSocketSession;
import reactor.core.publisher.Mono;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class AccountSessionGuardTest {
    @Test void closesAllDevicesForDeletedUserWithoutClosingAnotherPlayersSocket() {
        var users=mock(UserRepository.class); var guard=new AccountSessionGuard(users,new AgeSafetyService(mock(DatabaseClient.class),false));
        UUID user=UUID.randomUUID(),other=UUID.randomUUID();
        var first=mock(WebSocketSession.class);var second=mock(WebSocketSession.class);var kept=mock(WebSocketSession.class);
        when(first.close(any())).thenReturn(Mono.empty());when(second.close(any())).thenReturn(Mono.empty());
        guard.register(user,first);guard.register(user,second);guard.register(other,kept);
        guard.close(user).block();guard.close(user).block();
        verify(first,times(1)).close(any());verify(second,times(1)).close(any());verify(kept,never()).close(any());
    }

    @Test void seatedCyberAgentCanUseRoomChecksButCannotUseNormalAccountAccess() {
        var users=mock(UserRepository.class);var guard=new AccountSessionGuard(users,new AgeSafetyService(mock(DatabaseClient.class),false));UUID bot=UUID.randomUUID();
        when(users.findById(bot)).thenReturn(Mono.just(UserRow.newBot("Cyber", "cyber", null, "chess", "easy")));
        assertThat(guard.exists(bot).block()).isFalse();
        assertThatThrownBy(()->guard.require(bot).block()).isInstanceOf(SecurityException.class);
        assertThatCode(()->guard.requireRoomParticipant(bot).block()).doesNotThrowAnyException();
    }

    @Test void ordinaryPlayerCanUseBothAccountAndRoomChecks() {
        var users=mock(UserRepository.class);var guard=new AccountSessionGuard(users,new AgeSafetyService(mock(DatabaseClient.class),false));UUID user=UUID.randomUUID();
        when(users.findById(user)).thenReturn(Mono.just(UserRow.newGuest("device", "Player", "player")));
        assertThatCode(()->guard.require(user).block()).doesNotThrowAnyException();
        assertThatCode(()->guard.requireRoomParticipant(user).block()).doesNotThrowAnyException();
    }

    @Test void missingAccountCannotUseAnOtherwiseValidSession() {
        var users=mock(UserRepository.class);var guard=new AccountSessionGuard(users,new AgeSafetyService(mock(DatabaseClient.class),false));UUID user=UUID.randomUUID();
        when(users.findById(user)).thenReturn(Mono.empty());
        assertThat(guard.exists(user).block()).isFalse();
        assertThatThrownBy(()->guard.require(user).block()).isInstanceOf(SecurityException.class);
        assertThatThrownBy(()->guard.requireRoomParticipant(user).block()).isInstanceOf(SecurityException.class);
    }
}
