package app.truearena.api.auth;

import app.truearena.persistence.UserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.socket.WebSocketSession;
import reactor.core.publisher.Mono;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class AccountSessionGuardTest {
    @Test void closesAllDevicesForDeletedUserWithoutClosingAnotherPlayersSocket() {
        var users=mock(UserRepository.class); var guard=new AccountSessionGuard(users);
        UUID user=UUID.randomUUID(),other=UUID.randomUUID();
        var first=mock(WebSocketSession.class);var second=mock(WebSocketSession.class);var kept=mock(WebSocketSession.class);
        when(first.close(any())).thenReturn(Mono.empty());when(second.close(any())).thenReturn(Mono.empty());
        guard.register(user,first);guard.register(user,second);guard.register(other,kept);
        guard.close(user).block();guard.close(user).block();
        verify(first,times(1)).close(any());verify(second,times(1)).close(any());verify(kept,never()).close(any());
    }

    @Test void missingAccountCannotUseAnOtherwiseValidSession() {
        var users=mock(UserRepository.class);var guard=new AccountSessionGuard(users);UUID user=UUID.randomUUID();
        when(users.findById(user)).thenReturn(Mono.empty());
        assertThat(guard.exists(user).block()).isFalse();
        assertThatThrownBy(()->guard.require(user).block()).isInstanceOf(SecurityException.class);
    }
}
