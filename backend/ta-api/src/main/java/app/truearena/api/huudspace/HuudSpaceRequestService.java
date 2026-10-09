package app.truearena.api.huudspace;

import app.truearena.api.huudspace.HuudSpaceDtos.HuudSpaceView;
import app.truearena.api.room.RoomService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.voice.LiveKitRoomAdmin;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Asking the host, and the host answering. Being in a Huud means listening,
 * chatting and watching; a seat in the game and the mic are the host's to
 * hand out, and so is the door of a private Huud.
 */
@Service
public class HuudSpaceRequestService {

    static final Set<String> KINDS = Set.of("join", "play", "mic");

    private final HuudSpaceService huuds;
    private final RoomService rooms;
    private final LiveKitRoomAdmin voice;
    private final DatabaseClient db;

    public HuudSpaceRequestService(HuudSpaceService huuds, RoomService rooms, LiveKitRoomAdmin voice, DatabaseClient db) {
        this.huuds = huuds;
        this.rooms = rooms;
        this.voice = voice;
        this.db = db;
    }

    /** "Can I play?" — for the game being set up right now. */
    public Mono<HuudSpaceView> askToPlay(UUID user, UUID id) {
        return huuds.requireMember(id, user)
                .flatMap(s -> huuds.currentGame(s.currentRoomId(), user)
                        .switchIfEmpty(Mono.error(ApiExceptions.conflict("There's no game to play yet")))
                        .flatMap(game -> {
                            if (game.youArePlaying()) return Mono.error(ApiExceptions.conflict("You're already playing"));
                            if (!"waiting".equals(game.status())) {
                                return Mono.error(ApiExceptions.conflict("This game has already started — you can watch it"));
                            }
                            if (s.ownerId().equals(user)) return seat(s.id(), user, game.code());
                            return huuds.upsertRequest(id, user, "play", game.roomId())
                                    .doOnSuccess(v -> huuds.notify(s.ownerId(), id, "request", user));
                        }))
                .then(huuds.view(id, user));
    }

    /** "Can I talk?" */
    public Mono<HuudSpaceView> askForMic(UUID user, UUID id) {
        return huuds.requireMember(id, user)
                .flatMap(s -> huuds.membership(id, user).flatMap(m -> m.canSpeak() || s.ownerId().equals(user)
                        ? Mono.<Void>empty()
                        : huuds.upsertRequest(id, user, "mic", null)
                                .doOnSuccess(v -> huuds.notify(s.ownerId(), id, "request", user))))
                .then(huuds.view(id, user));
    }

    /** Host only: yes or no to someone's request. */
    public Mono<HuudSpaceView> answer(UUID host, UUID id, UUID target, String kind, boolean accept) {
        if (!KINDS.contains(kind)) return Mono.error(ApiExceptions.badRequest("unknown request"));
        return huuds.requireHost(id, host)
                .flatMap(s -> huuds.request(id, target, kind).filter("pending"::equals)
                        .switchIfEmpty(Mono.error(ApiExceptions.conflict("That request has already been answered")))
                        .then(Mono.defer(() -> !accept ? huuds.answerRow(id, target, kind, false)
                                : switch (kind) {
                                    case "join" -> huuds.admitRow(id, target)
                                            .then(huuds.answerRow(id, target, kind, true))
                                            .doOnSuccess(v -> huuds.notifyMembers(id, "joined", target));
                                    case "play" -> huuds.currentGame(s.currentRoomId(), target)
                                            .filter(game -> "waiting".equals(game.status()))
                                            .switchIfEmpty(Mono.error(ApiExceptions.conflict("That game isn't waiting for players any more")))
                                            .flatMap(game -> game.players() >= game.seats()
                                                    ? Mono.error(ApiExceptions.conflict("The game is full — no seats left"))
                                                    : seat(id, target, game.code()))
                                            .then(huuds.answerRow(id, target, kind, true));
                                    default -> speaker(id, target, true).then(huuds.answerRow(id, target, kind, true));
                                }))
                        .doOnSuccess(v -> huuds.notify(target, id, accept ? "accepted-" + kind : "declined-" + kind, host)))
                .then(huuds.view(id, host));
    }

    /** Host only: hand someone the mic, or take it back. */
    public Mono<HuudSpaceView> setMic(UUID host, UUID id, UUID target, boolean allowed) {
        return huuds.requireHost(id, host)
                .flatMap(s -> s.ownerId().equals(target) ? Mono.<Void>empty()
                        : huuds.membership(id, target).filter(HuudSpaceService.Membership::in)
                                .switchIfEmpty(Mono.error(ApiExceptions.notFound("They're not in the Huud")))
                                .then(speaker(id, target, allowed))
                                .then(huuds.request(id, target, "mic").filter("pending"::equals)
                                        .flatMap(p -> huuds.answerRow(id, target, "mic", allowed)))
                                .doOnSuccess(v -> huuds.notify(target, id, allowed ? "accepted-mic" : "mic-off", host)))
                .then(huuds.view(id, host));
    }

    /** Host only: invite a friend — they can come straight in, whatever the privacy. */
    public Mono<HuudSpaceView> invite(UUID host, UUID id, UUID friend) {
        return huuds.requireHost(id, host)
                .flatMap(s -> huuds.friends(host, friend).filter(Boolean::booleanValue)
                        .switchIfEmpty(Mono.error(ApiExceptions.forbidden("You can only invite your friends")))
                        .then(huuds.membership(id, friend).map(HuudSpaceService.Membership::removed).defaultIfEmpty(false))
                        .flatMap(removed -> removed
                                ? Mono.error(ApiExceptions.conflict("You took them out of this Huud"))
                                : huuds.answerRow(id, friend, "join", true))
                        .doOnSuccess(v -> huuds.notify(friend, id, "invited", host)))
                .then(huuds.view(id, host));
    }

    /**
     * Host only: put people from the Huud into the game's seats — no asking
     * needed. Only people in the Huud, only while the game is waiting, never
     * past the seats. Each one is told to get ready.
     */
    public Mono<HuudSpaceView> pick(UUID host, UUID id, List<UUID> people) {
        return huuds.requireHost(id, host)
                .flatMap(s -> huuds.currentGame(s.currentRoomId(), host)
                        .filter(game -> "waiting".equals(game.status()))
                        .switchIfEmpty(Mono.error(ApiExceptions.conflict("Pick a game first — or wait for this one to end")))
                        .flatMap(game -> {
                            var fresh = people.stream().distinct().filter(p -> !game.playerIds().contains(p)).toList();
                            if (game.players() + fresh.size() > game.seats()) {
                                return Mono.error(ApiExceptions.conflict(
                                        game.seats() - game.players() <= 0 ? "Every seat is taken"
                                                : "Only " + (game.seats() - game.players()) + " more can play"));
                            }
                            return Flux.fromIterable(fresh)
                                    .concatMap(p -> huuds.membership(id, p).filter(HuudSpaceService.Membership::in)
                                            .switchIfEmpty(Mono.error(ApiExceptions.badRequest("Players have to be in the Huud")))
                                            .then(rooms.join(game.code(), p, null))
                                            .then(huuds.request(id, p, "play").filter("pending"::equals)
                                                    .flatMap(q -> huuds.answerRow(id, p, "play", true)))
                                            .doOnSuccess(v -> huuds.notify(p, id, "picked", host)))
                                    .then();
                        })
                        .doOnSuccess(v -> huuds.notifyMembers(id, "game", host)))
                .then(huuds.view(id, host));
    }

    /** Host only: free someone's seat before the game starts. */
    public Mono<HuudSpaceView> unpick(UUID host, UUID id, UUID player) {
        return huuds.requireHost(id, host)
                .flatMap(s -> huuds.currentGame(s.currentRoomId(), host)
                        .switchIfEmpty(Mono.error(ApiExceptions.conflict("There's no game to change")))
                        .flatMap(game -> db.sql("SELECT host_id FROM rooms WHERE id=:id").bind("id", game.roomId())
                                .map((r, m) -> r.get("host_id", UUID.class)).one()
                                .flatMap(roomHost -> rooms.removeFromLobby(game.roomId(), roomHost, player)))
                        .doOnSuccess(v -> {
                            huuds.notify(player, id, "unpicked", host);
                            huuds.notifyMembers(id, "game", host);
                        }))
                .then(huuds.view(id, host));
    }

    /** A seat in the game: the room join everyone used to do by hand with the code. */
    private Mono<Void> seat(UUID id, UUID user, String roomCode) {
        return rooms.join(roomCode, user, null)
                .doOnSuccess(room -> huuds.notifyMembers(id, "game", user))
                .then();
    }

    private Mono<Void> speaker(UUID id, UUID user, boolean allowed) {
        return db.sql("UPDATE huud_space_members SET can_speak=:allowed WHERE huud_space_id=:id AND user_id=:user")
                .bind("allowed", allowed).bind("id", id).bind("user", user).fetch().rowsUpdated()
                // Already in the voice room? Flip it live; otherwise their next token carries it.
                .then(voice.setCanPublish(HuudSpaceAccess.VOICE_PREFIX + id, user.toString(), allowed)
                        .onErrorResume(e -> Mono.empty()));
    }
}
