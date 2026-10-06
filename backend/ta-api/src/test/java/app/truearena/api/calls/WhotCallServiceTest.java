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
import app.truearena.voice.LiveKitRoomAdmin;
import app.truearena.room.RoomRuntime;
import app.truearena.room.RoomRuntimeRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.util.UUID;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.verify;

class WhotCallServiceTest {
    private final UUID roomId = UUID.randomUUID();
    private final UUID playerId = UUID.randomUUID();
    private final RoomRepository rooms = mock(RoomRepository.class);
    private final RoomMemberRepository members = mock(RoomMemberRepository.class);
    private final UserRepository users = mock(UserRepository.class);
    private final LiveKitTokenService tokens = mock(LiveKitTokenService.class);
    private final LiveKitRoomAdmin voiceAdmin = mock(LiveKitRoomAdmin.class);
    private final RoomRuntimeRegistry runtimes = new RoomRuntimeRegistry();
    private final CallService service = new CallService(
            mock(FriendRepository.class), mock(GroupMemberRepository.class),
            members, rooms, users, tokens, runtimes, voiceAdmin);

    private RoomRow room(String game, String status) {
        return new RoomRow(roomId, "123456", null, playerId, status,
                game, 0, null, false, null);
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

    @Test
    void activePlayerGetsSharedGameVoiceAcrossModes() {
        when(rooms.findById(roomId)).thenReturn(Mono.just(room("wordbluff", "in_game")));
        when(members.findByRoomIdAndUserId(roomId, playerId))
                .thenReturn(Mono.just(RoomMemberRow.of(roomId, playerId, "Player")));
        when(users.findById(playerId)).thenReturn(Mono.just(new UserRow(playerId,
                "Player", null, null, null, null, false, null, false,
                null, null, null, null, null)));
        when(tokens.mintToken("game-" + roomId, playerId.toString(), "Player", true))
                .thenReturn("signed-token");
        when(tokens.wsUrl()).thenReturn("wss://voice.example.test");

        StepVerifier.create(service.gameCallToken(playerId, roomId))
                .expectNextMatches(value -> value.roomName().equals("game-" + roomId)
                        && value.token().equals("signed-token")
                        && value.livekitUrl().equals("wss://voice.example.test"))
                .verifyComplete();
    }

    @Test
    void approvedSpectatorCanJoinGameVoiceButMutedOrUnapprovedSpectatorCannot() {
        UUID viewerId = UUID.randomUUID();
        when(rooms.findById(roomId)).thenReturn(Mono.just(room("draughts", "in_game")));
        when(members.findByRoomIdAndUserId(roomId, viewerId)).thenReturn(Mono.empty());
        when(users.findById(viewerId)).thenReturn(Mono.just(new UserRow(viewerId,
                "Viewer", null, null, null, null, false, null, false,
                null, null, null, null, null)));
        when(tokens.mintToken("game-" + roomId, viewerId.toString(), "Viewer", false))
                .thenReturn("spectator-token");
        when(tokens.wsUrl()).thenReturn("wss://voice.example.test");

        RoomRuntime runtime = runtimes.computeIfAbsent(roomId,
                ignored -> new RoomRuntime(roomId, playerId.toString()));
        runtime.spectatorUserIds.add(viewerId.toString());

        StepVerifier.create(service.gameCallToken(viewerId, roomId))
                .expectErrorMatches(error -> error instanceof ResponseStatusException ex
                        && ex.getStatusCode().value() == 403).verify();

        runtime.spectatorVoiceSpeakers.add(viewerId.toString());
        StepVerifier.create(service.gameCallToken(viewerId, roomId))
                .expectNextMatches(value -> value.token().equals("spectator-token"))
                .verifyComplete();

        when(voiceAdmin.setCanPublish("game-" + roomId, viewerId.toString(), true))
                .thenReturn(Mono.empty());
        StepVerifier.create(service.activateSpectatorVoice(viewerId, roomId)).verifyComplete();
        verify(voiceAdmin).setCanPublish("game-" + roomId, viewerId.toString(), true);

        runtime.mutedSpectatorVoiceSpeakers.add(viewerId.toString());
        StepVerifier.create(service.gameCallToken(viewerId, roomId))
                .expectErrorMatches(error -> error instanceof ResponseStatusException ex
                        && ex.getStatusCode().value() == 403).verify();
        StepVerifier.create(service.activateSpectatorVoice(viewerId, roomId))
                .expectErrorMatches(error -> error instanceof ResponseStatusException ex
                        && ex.getStatusCode().value() == 403).verify();
    }
}
