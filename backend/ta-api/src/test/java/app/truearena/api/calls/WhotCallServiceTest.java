package app.truearena.api.calls;

import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.GroupMemberRepository;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.voice.LiveKitTokenService;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.util.UUID;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class WhotCallServiceTest {
    private final UUID roomId = UUID.randomUUID();
    private final UUID playerId = UUID.randomUUID();
    private final RoomRepository rooms = mock(RoomRepository.class);
    private final RoomMemberRepository members = mock(RoomMemberRepository.class);
    private final UserRepository users = mock(UserRepository.class);
    private final LiveKitTokenService tokens = mock(LiveKitTokenService.class);
    private final CallService service = new CallService(
            mock(FriendRepository.class), mock(GroupMemberRepository.class),
            members, rooms, users, tokens);

    private RoomRow room(String game, String status) {
        return new RoomRow(roomId, "123456", null, playerId, status,
                game, 0, null, null);
    }

    @Test
    void activeWhotPlayerGetsTheSameVoiceRoom() {
        when(rooms.findById(roomId)).thenReturn(Mono.just(room("whot", "in_game")));
        when(members.findByRoomIdAndUserId(roomId, playerId))
                .thenReturn(Mono.just(RoomMemberRow.of(roomId, playerId, "Player")));
        when(users.findById(playerId)).thenReturn(Mono.just(new UserRow(playerId,
                "Player", null, null, null, null, false, null, false,
                null, null, null, null, null)));
        when(tokens.mintToken("whot-" + roomId, playerId.toString(), "Player"))
                .thenReturn("signed-token");
        when(tokens.wsUrl()).thenReturn("ws://localhost:7880");

        StepVerifier.create(service.whotCallToken(playerId, roomId))
                .expectNextMatches(value -> value.roomName().equals("whot-" + roomId)
                        && value.token().equals("signed-token"))
                .verifyComplete();
    }

    @Test
    void spectatorsAndOtherGamesCannotJoinWhotVoice() {
        when(rooms.findById(roomId)).thenReturn(Mono.just(room("whot", "in_game")));
        when(members.findByRoomIdAndUserId(roomId, playerId)).thenReturn(Mono.empty());
        when(users.findById(playerId)).thenReturn(Mono.empty());
        StepVerifier.create(service.whotCallToken(playerId, roomId))
                .expectErrorMatches(error -> error instanceof ResponseStatusException ex
                        && ex.getStatusCode().value() == 403).verify();

        when(rooms.findById(roomId)).thenReturn(Mono.just(room("wordbluff", "in_game")));
        StepVerifier.create(service.whotCallToken(playerId, roomId))
                .expectErrorMatches(error -> error instanceof ResponseStatusException ex
                        && ex.getStatusCode().value() == 404).verify();
    }
}
