package app.truearena.api.huudspace;

import app.truearena.api.championship.ChampionshipEvents;
import app.truearena.api.championship.ChampionshipService;
import app.truearena.api.huudspace.HuudSpaceDtos.ChampionshipMatch;
import app.truearena.api.huudspace.HuudSpaceDtos.ChampionshipRequest;
import app.truearena.api.huudspace.HuudSpaceDtos.Entrant;
import app.truearena.api.huudspace.HuudSpaceDtos.HuudChampionship;
import app.truearena.api.huudspace.HuudSpaceService.Space;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.ChampionshipRepository;
import app.truearena.persistence.ChampionshipRow;
import app.truearena.room.RoomRuntimeRegistry;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * A championship inside a Huud — the Huud's one exception to "one game at a
 * time": several boards of the same game, all belonging to one bracket.
 *
 * <p>The Huud stays the platform: its members register, its chat stays the
 * one chat, its mic rules decide who speaks. Its own voice room is the
 * championship lobby; each match being played gets a voice room of its own
 * ({@link HuudSpaceAccess#matchVoiceRoom}). The bracket itself — draw, rounds,
 * draws replayed, disconnects, forfeits, byes, the champion — is
 * {@link ChampionshipService}'s, unchanged.
 */
@Service
public class HuudChampionshipService implements ChampionshipEvents {

    static final Map<String, String> GAME_NAMES = Map.of("chess", "Chess", "draughts", "Draughts");

    private final HuudSpaceService huuds;
    private final ChampionshipService championships;
    private final ChampionshipRepository rows;
    private final RoomRuntimeRegistry runtimes;
    private final DatabaseClient db;

    public HuudChampionshipService(HuudSpaceService huuds, ChampionshipService championships,
                                   ChampionshipRepository rows, RoomRuntimeRegistry runtimes, DatabaseClient db) {
        this.huuds = huuds;
        this.championships = championships;
        this.rows = rows;
        this.runtimes = runtimes;
        this.db = db;
    }

    /**
     * Host only, while Live: open registration. A game waiting for players is
     * put away; one being played has to finish first. A finished championship
     * still showing its bracket makes way for the new one.
     */
    public Mono<HuudChampionship> create(UUID host, UUID id, ChampionshipRequest request) {
        String gameType = request.gameType() == null ? "" : request.gameType().trim().toLowerCase();
        int size = request.size() == null ? 8 : request.size();
        String timing = request.roundTiming() == null ? "simultaneous" : request.roundTiming().trim().toLowerCase();
        boolean watching = request.spectatorsAllowed() == null || request.spectatorsAllowed();
        int grace = (request.graceMinutes() == null ? 3 : request.graceMinutes()) * 60;
        String name = request.name() == null || request.name().isBlank()
                ? GAME_NAMES.getOrDefault(gameType, "") + " Championship" : request.name();
        return huuds.requireHost(id, host)
                .filter(Space::live)
                .switchIfEmpty(Mono.error(ApiExceptions.conflict("Go Live first, then start a championship")))
                .flatMap(s -> huuds.championshipOn(s).flatMap(on -> on
                        ? Mono.<Space>error(ApiExceptions.conflict("There's already a championship in this Huud"))
                        : Mono.just(s)))
                .flatMap(s -> huuds.currentGame(s.currentRoomId(), null)
                        .flatMap(game -> "playing".equals(game.status())
                                ? Mono.<Space>error(ApiExceptions.conflict("Finish the game that's on first"))
                                : huuds.cancelWaitingGame(s, host).thenReturn(s))
                        .defaultIfEmpty(s))
                .flatMap(s -> championships.createInHuud(host, id, name, gameType, size, timing, watching, grace))
                .flatMap(c -> db.sql("UPDATE huud_spaces SET championship_id=:c, current_room_id=NULL WHERE id=:id")
                        .bind("c", c.id()).bind("id", id).fetch().rowsUpdated()
                        .then(db.sql("DELETE FROM huud_space_requests WHERE huud_space_id=:id AND kind='play'")
                                .bind("id", id).fetch().rowsUpdated()))
                .doOnSuccess(n -> huuds.notifyMembers(id, "championship", host))
                .then(view(id, host));
    }

    /** What everyone allowed to look into the Huud sees: registration, the bracket, the result. */
    public Mono<HuudChampionship> view(UUID id, UUID viewer) {
        return huuds.space(id).filter(Space::active)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("That Huud isn't here any more")))
                .flatMap(s -> mayLook(s, viewer).flatMap(ok -> ok ? Mono.just(s)
                        : Mono.error(ApiExceptions.forbidden("This Huud isn't open to you"))))
                .flatMap(s -> s.championshipId() == null
                        ? Mono.error(ApiExceptions.notFound("There's no championship in this Huud"))
                        : rows.findById(s.championshipId()))
                .flatMap(c -> build(c, viewer));
    }

    /** A member, or someone the Huud lets watch. */
    private Mono<Boolean> mayLook(Space s, UUID viewer) {
        return huuds.membership(s.id(), viewer).map(HuudSpaceService.Membership::in).defaultIfEmpty(false)
                .flatMap(member -> member ? Mono.just(true) : huuds.blocked(viewer, s.createdBy())
                        .flatMap(blocked -> blocked ? Mono.just(false) : huuds.canSee(s, viewer)));
    }

    private Mono<HuudChampionship> build(ChampionshipRow c, UUID viewer) {
        Mono<List<Entrant>> people = db.sql("SELECT p.user_id, u.display_name, u.username, u.avatar_url "
                        + "FROM championship_participants p JOIN users u ON u.id=p.user_id "
                        + "WHERE p.championship_id=:c ORDER BY p.slot")
                .bind("c", c.id())
                .map((r, m) -> new Entrant(r.get("user_id", UUID.class), r.get("display_name", String.class),
                        r.get("username", String.class), r.get("avatar_url", String.class), false))
                .all().collectList();
        return Mono.zip(people, championships.bracket(c.id())).map(t -> {
            int rounds = Integer.numberOfTrailingZeros(c.size());
            Set<UUID> out = new HashSet<>();
            List<ChampionshipMatch> matches = t.getT2().stream().map(m -> {
                if ("completed".equals(m.status()) || "no_winner".equals(m.status())) {
                    if (m.playerA() != null && !m.playerA().equals(m.winnerId())) out.add(m.playerA());
                    if (m.playerB() != null && !m.playerB().equals(m.winnerId())) out.add(m.playerB());
                }
                boolean active = "active".equals(m.status());
                int watching = active && m.roomId() != null
                        ? runtimes.find(m.roomId()).map(rt -> rt.spectatorUserIds.size()).orElse(0) : 0;
                return new ChampionshipMatch(m.id(), m.round(), roundName(m.round(), rounds), m.position(),
                        m.playerA(), m.playerB(), m.winnerId(), m.status(), active ? m.roomId() : null,
                        m.gameNumber(), watching,
                        active ? HuudSpaceAccess.matchVoiceRoom(c.huudSpaceId(), m.id()) : null,
                        m.aReconnectMs(), m.bReconnectMs());
            }).toList();
            List<Entrant> players = t.getT1().stream().map(p -> new Entrant(p.userId(), p.name(), p.username(),
                    p.avatarUrl(), out.contains(p.userId()))).toList();
            ChampionshipMatch last = matches.stream().filter(m -> m.round() == rounds).findFirst().orElse(null);
            UUID runnerUp = c.championId() == null || last == null ? null
                    : c.championId().equals(last.playerA()) ? last.playerB() : last.playerA();
            UUID yours = matches.stream()
                    .filter(m -> "active".equals(m.status())
                            && (viewer.equals(m.playerA()) || viewer.equals(m.playerB())))
                    .map(ChampionshipMatch::id).findFirst().orElse(null);
            return new HuudChampionship(c.id(), c.huudSpaceId(), c.name(), c.gameType(), c.size(), status(c.status()),
                    c.roundTiming(), c.spectatorsAllowed(), c.graceSeconds(), c.currentRound(), rounds,
                    c.currentRound() == 0 ? null : roundName(c.currentRound(), rounds), players,
                    players.stream().anyMatch(p -> p.userId().equals(viewer)), matches, c.championId(), runnerUp,
                    yours, HuudSpaceAccess.VOICE_PREFIX + c.huudSpaceId(), c.creatorId());
        });
    }

    /** Rounds are named from the end: the Final, Semi Finals, Quarter Finals, then Round of 16. */
    static String roundName(int round, int rounds) {
        return switch (rounds - round) {
            case 0 -> "Final";
            case 1 -> "Semi Finals";
            case 2 -> "Quarter Finals";
            default -> "Round of " + (1 << (rounds - round + 1));
        };
    }

    static String status(String championshipStatus) {
        return switch (championshipStatus) {
            case "lobby" -> "registering";
            case "running" -> "playing";
            case "completed" -> "finished";
            default -> championshipStatus;
        };
    }

    /** A member in the Live hangout takes a place. The last place starts the draw. */
    public Mono<HuudChampionship> register(UUID user, UUID id) {
        return huuds.requireMember(id, user)
                .filter(Space::live)
                .switchIfEmpty(Mono.error(ApiExceptions.conflict("The Huud isn't Live right now")))
                .flatMap(s -> current(s)
                        .flatMap(c -> championships.register(c, user)))
                .then(view(id, user));
    }

    /** Give your place back while registration is open. */
    public Mono<HuudChampionship> withdraw(UUID user, UUID id) {
        return huuds.requireMember(id, user)
                .flatMap(this::current)
                .flatMap(c -> championships.withdraw(c.id(), user))
                .then(view(id, user));
    }

    /** Host only, while registration is open: free someone's place. */
    public Mono<HuudChampionship> removePlayer(UUID host, UUID id, UUID player) {
        return huuds.requireHost(id, host)
                .flatMap(this::current)
                .flatMap(c -> championships.withdraw(c.id(), player))
                .then(view(id, host));
    }

    /**
     * Host only: back to hanging out. Calls off a championship still taking
     * registrations; puts a finished one's bracket away. One being played
     * can't be — its matches are real games with real results.
     */
    public Mono<HuudSpaceDtos.HuudSpaceView> close(UUID host, UUID id) {
        return huuds.requireHost(id, host)
                .flatMap(s -> s.championshipId() == null ? Mono.<Void>empty()
                        : rows.findById(s.championshipId()).flatMap(c -> "running".equals(c.status())
                                ? Mono.<Void>error(ApiExceptions.conflict("The championship is still being played"))
                                : championships.cancel(c.id()).then(huuds.putChampionshipAway(id))))
                .doOnSuccess(v -> huuds.notifyMembers(id, "championship", host))
                .then(huuds.view(id, host));
    }

    /** Host only: both players have been gone past their allowance — the pairing ends with no winner. */
    public Mono<HuudChampionship> endBothAbsent(UUID host, UUID id, UUID matchId) {
        return huuds.requireHost(id, host)
                .flatMap(this::current)
                .flatMap(c -> db.sql("SELECT EXISTS(SELECT 1 FROM championship_matches WHERE id=:m AND championship_id=:c) AS ok")
                        .bind("m", matchId).bind("c", c.id())
                        .map((r, m) -> Boolean.TRUE.equals(r.get("ok", Boolean.class))).one()
                        .flatMap(ok -> ok ? championships.endBothAbsent(matchId, c.creatorId())
                                : Mono.error(ApiExceptions.notFound("That match isn't in this championship"))))
                .then(view(id, host));
    }

    private Mono<ChampionshipRow> current(Space s) {
        if (s.championshipId() == null) return Mono.error(ApiExceptions.notFound("There's no championship in this Huud"));
        return rows.findById(s.championshipId())
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("There's no championship in this Huud")));
    }

    // ------------------------------------------------------------ the bracket tells the Huud

    @Override
    public void changed(UUID championshipId) {
        huudOf(championshipId).subscribe(h -> huuds.notifyMembers(h.getKey(), "championship", h.getValue()), e -> { });
    }

    /** Both players hear their board is ready — a push if they're away. */
    @Override
    public void matchReady(UUID championshipId, UUID matchId, UUID playerA, UUID playerB) {
        huudOf(championshipId).subscribe(h -> {
            huuds.notify(playerA, h.getKey(), "championship-match", h.getValue());
            huuds.notify(playerB, h.getKey(), "championship-match", h.getValue());
        }, e -> { });
    }

    /** The championship's Huud and who started it — empty for a standalone championship. */
    private Mono<Map.Entry<UUID, UUID>> huudOf(UUID championshipId) {
        return db.sql("SELECT huud_space_id, creator_id FROM championships WHERE id=:id AND huud_space_id IS NOT NULL")
                .bind("id", championshipId)
                .map((r, m) -> Map.entry(r.get("huud_space_id", UUID.class), r.get("creator_id", UUID.class)))
                .one();
    }
}
