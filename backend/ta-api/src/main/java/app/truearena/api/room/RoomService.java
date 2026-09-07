package app.truearena.api.room;

import app.truearena.api.auth.JwtService;
import app.truearena.api.room.RoomDtos.RoomMemberView;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.security.SecureRandom;
import java.util.UUID;

@Service
public class RoomService {

    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no O/0/I/1
    private static final int MAX_PLAYERS = 16;
    private static final SecureRandom RNG = new SecureRandom();

    private final RoomRepository rooms;
    private final RoomMemberRepository members;
    private final JwtService jwt;

    public RoomService(RoomRepository rooms, RoomMemberRepository members, JwtService jwt) {
        this.rooms = rooms;
        this.members = members;
        this.jwt = jwt;
    }

    public Mono<RoomView> create(UUID hostId, UUID groupId) {
        return allocateCode(5)
                .flatMap(code -> rooms.save(RoomRow.create(code, groupId, hostId)))
                .flatMap(room -> members.save(RoomMemberRow.of(room.id(), hostId, null)).thenReturn(room))
                .flatMap(room -> view(room, hostId));
    }

    public Mono<RoomView> join(String code, UUID userId, String nickname) {
        return rooms.findByCode(code.toUpperCase())
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no room with that code")))
                .flatMap(room -> members.findByRoomIdAndUserId(room.id(), userId)
                        .flatMap(existing -> view(room, userId))
                        .switchIfEmpty(members.countByRoomId(room.id())
                                .flatMap(count -> count >= MAX_PLAYERS
                                        ? Mono.error(ApiExceptions.conflict("room is full"))
                                        : members.save(RoomMemberRow.of(room.id(), userId, nickname))
                                        .then(view(room, userId)))));
    }

    public Mono<RoomView> get(UUID roomId, UUID userId) {
        return rooms.findById(roomId)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("room not found")))
                .flatMap(room -> view(room, userId));
    }

    private Mono<RoomView> view(RoomRow room, UUID viewerId) {
        return members.findByRoomId(room.id())
                .map(m -> new RoomMemberView(m.userId(), m.nickname(), m.connectionStatus(), m.readyState()))
                .collectList()
                .map(list -> new RoomView(
                        room.id(), room.code(), room.groupId(), room.hostId(), room.status(), room.createdAt(),
                        list, "/ws/room/" + room.id(), jwt.issueAccess(viewerId)));
    }

    private Mono<String> allocateCode(int attemptsLeft) {
        String candidate = randomCode();
        return rooms.findByCode(candidate)
                .flatMap(existing -> attemptsLeft > 0
                        ? allocateCode(attemptsLeft - 1)
                        : Mono.<String>error(ApiExceptions.conflict("could not allocate a room code")))
                .switchIfEmpty(Mono.just(candidate));
    }

    private static String randomCode() {
        StringBuilder sb = new StringBuilder(6);
        for (int i = 0; i < 6; i++) {
            sb.append(ALPHABET.charAt(RNG.nextInt(ALPHABET.length())));
        }
        return sb.toString();
    }
}
