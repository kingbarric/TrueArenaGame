package app.truearena.api.bot;

import app.truearena.api.auth.JwtService;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.room.RoomLock;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.time.Instant;
import java.util.UUID;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class BotServicePoolTest {

    @Test
    @SuppressWarnings("unchecked")
    void sameSystemIdentityCanServeTwoRoomsWithIndependentNamesAndDifficulty() {
        UUID hostId = UUID.randomUUID();
        UUID firstRoom = UUID.randomUUID();
        UUID secondRoom = UUID.randomUUID();
        UUID agentId = UUID.randomUUID();
        RoomRepository rooms = mock(RoomRepository.class);
        RoomMemberRepository members = mock(RoomMemberRepository.class);
        UserRepository users = mock(UserRepository.class);
        RoomLock lock = mock(RoomLock.class);
        GameBotAdapterFactory adapters = mock(GameBotAdapterFactory.class);
        BotService service = spy(service(rooms, members, users, adapters, lock));
        UserRow poolAgent = UserRow.newBot("Cyber Agent", "system_agent_01", null,
                "system_pool", "medium");
        poolAgent = new UserRow(agentId, poolAgent.displayName(), null, null, null, poolAgent.username(),
                false, null, true, null, "system_pool", "medium", null, Instant.now());

        when(rooms.findById(firstRoom)).thenReturn(Mono.just(room(firstRoom, hostId)));
        when(rooms.findById(secondRoom)).thenReturn(Mono.just(room(secondRoom, hostId)));
        when(members.countByRoomId(any())).thenReturn(Mono.just(1L));
        when(users.findSystemAgentForRoom(any())).thenReturn(Mono.just(poolAgent));
        when(members.save(any())).thenAnswer(call -> Mono.just(call.getArgument(0)));
        when(adapters.create("whot")).thenReturn(new WhotBotAdapter());
        when(lock.withLock(any(), any(), any())).thenAnswer(call ->
                ((Supplier<Mono<?>>) call.getArgument(2)).get());
        doNothing().when(service).startRuntime(any(), any(), any(), any());

        StepVerifier.create(service.addBot(firstRoom, hostId, "Ama", "easy"))
                .assertNext(view -> {
                    assertThat(view.userId()).isEqualTo(agentId);
                    assertThat(view.displayName()).isEqualTo("Ama");
                    assertThat(view.difficulty()).isEqualTo("easy");
                }).verifyComplete();
        StepVerifier.create(service.addBot(secondRoom, hostId, "Kofi", "hard"))
                .assertNext(view -> {
                    assertThat(view.userId()).isEqualTo(agentId);
                    assertThat(view.displayName()).isEqualTo("Kofi");
                    assertThat(view.difficulty()).isEqualTo("hard");
                }).verifyComplete();

        ArgumentCaptor<RoomMemberRow> saved = ArgumentCaptor.forClass(RoomMemberRow.class);
        verify(members, org.mockito.Mockito.times(2)).save(saved.capture());
        assertThat(saved.getAllValues()).extracting(RoomMemberRow::roomId)
                .containsExactly(firstRoom, secondRoom);
        assertThat(saved.getAllValues()).extracting(RoomMemberRow::nickname)
                .containsExactly("Ama", "Kofi");
        assertThat(saved.getAllValues()).extracting(RoomMemberRow::botDifficulty)
                .containsExactly("easy", "hard");
    }

    @Test
    @SuppressWarnings("unchecked")
    void poolExhaustionIsReportedWithoutAnyOtherHuudConflict() {
        UUID hostId = UUID.randomUUID();
        UUID roomId = UUID.randomUUID();
        RoomRepository rooms = mock(RoomRepository.class);
        RoomMemberRepository members = mock(RoomMemberRepository.class);
        UserRepository users = mock(UserRepository.class);
        RoomLock lock = mock(RoomLock.class);
        GameBotAdapterFactory adapters = mock(GameBotAdapterFactory.class);
        BotService service = service(rooms, members, users, adapters, lock);

        when(rooms.findById(roomId)).thenReturn(Mono.just(room(roomId, hostId)));
        when(members.countByRoomId(roomId)).thenReturn(Mono.just(1L));
        when(users.findSystemAgentForRoom(roomId)).thenReturn(Mono.empty());
        when(adapters.create("whot")).thenReturn(new WhotBotAdapter());
        when(lock.withLock(eq(roomId), any(), any())).thenAnswer(call ->
                ((Supplier<Mono<?>>) call.getArgument(2)).get());

        StepVerifier.create(service.addBot(roomId, hostId, "Cyber", "medium"))
                .expectErrorMatches(error -> error instanceof ResponseStatusException response
                        && response.getStatusCode().value() == 409
                        && response.getReason().equals("no Cyber Agent seat is available"))
                .verify();
    }

    @Test
    void savedAgentInventoryIsEmpty() {
        BotService service = service(mock(RoomRepository.class), mock(RoomMemberRepository.class),
                mock(UserRepository.class), mock(GameBotAdapterFactory.class), mock(RoomLock.class));
        StepVerifier.create(service.listAgents(UUID.randomUUID(), "ludo")).verifyComplete();
    }

    @Test
    void runtimeRegistryStopsOnlyTheRequestedRoom() {
        UUID firstRoom = UUID.randomUUID();
        UUID secondRoom = UUID.randomUUID();
        UUID sharedAgent = UUID.randomUUID();
        BotRuntime first = mock(BotRuntime.class);
        BotRuntime second = mock(BotRuntime.class);
        BotRuntimeRegistry registry = new BotRuntimeRegistry();

        registry.register(firstRoom, sharedAgent, first);
        registry.register(secondRoom, sharedAgent, second);
        registry.stop(firstRoom, sharedAgent);

        verify(first).stop();
        verify(second, org.mockito.Mockito.never()).stop();
        registry.stopRoom(secondRoom);
        verify(second).stop();
    }

    private static RoomRow room(UUID roomId, UUID hostId) {
        return new RoomRow(roomId, "ABCDEF", null, hostId, "lobby", "whot", 0, null, false, Instant.now());
    }

    private static BotService service(RoomRepository rooms, RoomMemberRepository members,
                                      UserRepository users, GameBotAdapterFactory adapters, RoomLock lock) {
        return new BotService(rooms, members, users, mock(JwtService.class), new ObjectMapper(),
                adapters, mock(LlmMovePicker.class), mock(BotRuntimeRegistry.class), lock);
    }
}
