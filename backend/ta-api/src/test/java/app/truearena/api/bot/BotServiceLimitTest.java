package app.truearena.api.bot;

import app.truearena.api.auth.JwtService;
import app.truearena.api.auth.UsernameGenerator;
import app.truearena.api.coins.CoinService;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.room.RoomLock;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.time.Instant;
import java.util.Collections;
import java.util.UUID;
import java.util.function.Supplier;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class BotServiceLimitTest {

    @Test
    @SuppressWarnings("unchecked")
    void sixthAgentIsRejectedBeforeChargingCoins() {
        UUID hostId = UUID.randomUUID();
        UUID roomId = UUID.randomUUID();
        RoomRepository rooms = mock(RoomRepository.class);
        UserRepository users = mock(UserRepository.class);
        CoinService coins = mock(CoinService.class);
        RoomLock lock = mock(RoomLock.class);
        GameBotAdapterFactory adapters = mock(GameBotAdapterFactory.class);
        BotService service = new BotService(rooms, mock(RoomMemberRepository.class), users,
                mock(UsernameGenerator.class), mock(JwtService.class), new ObjectMapper(),
                adapters, mock(LlmMovePicker.class), mock(BotRuntimeRegistry.class), coins, lock);

        when(rooms.findById(roomId)).thenReturn(Mono.just(new RoomRow(roomId, "ABCDEF", null,
                hostId, "lobby", "whot", 0, null, Instant.now())));
        when(adapters.create("whot")).thenReturn(new WhotBotAdapter());
        when(users.findAgentsOf(hostId)).thenReturn(Flux.fromIterable(Collections.nCopies(5,
                UserRow.newBot("Agent", "agent", hostId, "all", "easy"))));
        when(lock.withLock(eq(hostId), any(), any())).thenAnswer(invocation ->
                ((Supplier<Mono<?>>) invocation.getArgument(2)).get());

        StepVerifier.create(service.addBot(roomId, hostId, "Sixth", "easy"))
                .expectErrorMatches(error -> error instanceof ResponseStatusException response
                        && response.getStatusCode().value() == 409
                        && response.getReason().contains("up to 5"))
                .verify();

        verify(coins, never()).debit(any(), anyLong(), any(), any());
    }
}
