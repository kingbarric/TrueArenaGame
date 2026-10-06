package app.truearena.api.championship;

import app.truearena.api.support.ApiExceptions;
import app.truearena.api.ws.GameOrchestrator;
import app.truearena.persistence.*;
import app.truearena.room.RoomRuntime;
import app.truearena.room.RoomRuntimeRegistry;
import app.truearena.room.LobbyBroadcast;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Persistent, game-agnostic knockout bracket. Draughts rooms are its first match adapter. */
@Service
public class ChampionshipService {
    private static final Logger log = LoggerFactory.getLogger(ChampionshipService.class);
    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final SecureRandom RNG = new SecureRandom();
    private static final long GRACE_MS = Duration.ofMinutes(3).toMillis();

    private final ChampionshipRepository championships;
    private final ChampionshipMatchRepository matches;
    private final UserRepository users;
    private final RoomRepository rooms;
    private final RoomMemberRepository members;
    private final RoomRuntimeRegistry runtimes;
    private final DatabaseClient db;
    private final ObjectProvider<GameOrchestrator> games;

    public ChampionshipService(ChampionshipRepository championships, ChampionshipMatchRepository matches,
                               UserRepository users, RoomRepository rooms, RoomMemberRepository members,
                               RoomRuntimeRegistry runtimes, DatabaseClient db,
                               ObjectProvider<GameOrchestrator> games) {
        this.championships = championships;
        this.matches = matches;
        this.users = users;
        this.rooms = rooms;
        this.members = members;
        this.runtimes = runtimes;
        this.db = db;
        this.games = games;
    }

    public record Person(UUID id, String name, int slot) {}
    public record Match(UUID id, int round, int position, UUID playerA, UUID playerB,
                        UUID winnerId, String status, UUID roomId, int gameNumber,
                        long aReconnectMs, long bReconnectMs) {}
    public record View(UUID id, String code, String name, String gameType, int size,
                       String visibility, Instant scheduledAt, UUID creatorId, String status,
                       int currentRound, UUID championId, int joined,
                       List<Person> participants, List<Match> matches, String inviteLink) {}
    public record Invitation(UUID id, String code, String name, String gameType, int size,
                             String visibility, Instant scheduledAt, String status, int joined) {}
    public record Badge(UUID championshipId, String name, Instant awardedAt) {}

    public Flux<Badge> badges(UUID user) {
        return db.sql("SELECT b.championship_id,c.name,b.awarded_at FROM championship_badges b "
                        + "JOIN championships c ON c.id=b.championship_id WHERE b.user_id=:u ORDER BY b.awarded_at DESC")
                .bind("u", user).map((r, m) -> new Badge(r.get("championship_id", UUID.class),
                        r.get("name", String.class), r.get("awarded_at", Instant.class))).all();
    }

    public Mono<Invitation> publicInvitation(String code) {
        return championships.findByCode(code.toUpperCase())
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("invitation not found")))
                .flatMap(c -> db.sql("SELECT count(*) AS joined FROM championship_participants WHERE championship_id=:c")
                        .bind("c", c.id()).map((r, m) -> r.get("joined", Long.class)).one()
                        .map(count -> new Invitation(c.id(), c.code(), c.name(), c.gameType(), c.size(),
                                c.visibility(), c.scheduledAt(), c.status(), count.intValue())));
    }

    public Mono<View> create(UUID creator, String name, int size, String visibility, Instant start) {
        if (name == null || name.isBlank() || name.length() > 80 || !List.of(4, 8, 16, 32).contains(size))
            return Mono.error(ApiExceptions.badRequest("name and a size of 4, 8, 16 or 32 are required"));
        if (!List.of("public", "private").contains(visibility) || start == null || !start.isAfter(Instant.now()))
            return Mono.error(ApiExceptions.badRequest("choose visibility and a future start time"));
        return users.findById(creator)
                .filter(u -> !u.isBot() && !u.isGuest())
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("an account is required to create a championship")))
                .flatMap(u -> championships.save(ChampionshipRow.create(code(), name.trim(), size, visibility, start, creator)))
                .flatMap(c -> db.sql("INSERT INTO championship_participants(championship_id,user_id,slot) VALUES(:c,:u,1)")
                        .bind("c", c.id()).bind("u", creator).fetch().rowsUpdated().thenReturn(c))
                .flatMap(c -> detail(c.id(), creator));
    }

    public Mono<View> join(UUID id, UUID user) {
        return users.findById(user)
                .filter(u -> !u.isBot())
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("Cyber Agents cannot join championships")))
                .then(championships.findById(id).switchIfEmpty(Mono.error(ApiExceptions.notFound("championship not found"))))
                .flatMap(c -> isParticipant(id, user).flatMap(joined -> {
                    if (joined) return detail(id, user);
                    if (!"lobby".equals(c.status())) return Mono.error(ApiExceptions.conflict("registration is closed"));
                    // The slot uniqueness constraint protects capacity under concurrent joins.
                    return Flux.range(0, 4).concatMap(attempt -> db.sql(
                                    "INSERT INTO championship_participants(championship_id,user_id,slot) "
                                            + "SELECT :c,:u,COALESCE(MAX(slot),0)+1 FROM championship_participants "
                                            + "WHERE championship_id=:c HAVING COALESCE(MAX(slot),0)<:size "
                                            + "ON CONFLICT DO NOTHING")
                            .bind("c", id).bind("u", user).bind("size", c.size())
                            .fetch().rowsUpdated())
                            .filter(n -> n > 0).next()
                            .switchIfEmpty(isParticipant(id, user).flatMap(alreadyJoined -> alreadyJoined
                                    ? Mono.just(1L) : Mono.error(ApiExceptions.conflict("championship is full"))))
                            .then(tryStart(c)).then(detail(id, user));
                }));
    }

    public Mono<View> invitation(String code, UUID viewer) {
        return championships.findByCode(code.toUpperCase())
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("invitation not found")))
                .flatMap(c -> isParticipant(c.id(), viewer).flatMap(joined -> view(c, joined, false)));
    }

    public Mono<View> detail(UUID id, UUID viewer) {
        return championships.findById(id).switchIfEmpty(Mono.error(ApiExceptions.notFound("championship not found")))
                .flatMap(c -> isParticipant(id, viewer).flatMap(joined -> {
                    if (!joined && !"public".equals(c.visibility()))
                        return Mono.error(ApiExceptions.forbidden("private championship"));
                    return view(c, true, true);
                }));
    }

    public Flux<View> discover(UUID viewer) {
        return championships.findByVisibilityOrderByCreatedAtDesc("public")
                .concatMap(c -> view(c, true, false));
    }

    public Flux<View> mine(UUID viewer) {
        return db.sql("SELECT c.id FROM championships c JOIN championship_participants p "
                        + "ON p.championship_id=c.id WHERE p.user_id=:u ORDER BY c.created_at DESC")
                .bind("u", viewer).map((row, meta) -> row.get("id", UUID.class)).all()
                .concatMap(id -> detail(id, viewer));
    }

    private Mono<View> view(ChampionshipRow c, boolean includePeople, boolean includeMatches) {
        Mono<List<Person>> people = db.sql("SELECT p.user_id,p.slot,u.display_name FROM championship_participants p "
                        + "JOIN users u ON u.id=p.user_id WHERE p.championship_id=:c ORDER BY p.slot")
                .bind("c", c.id()).map((r, m) -> new Person(r.get("user_id", UUID.class),
                        r.get("display_name", String.class), r.get("slot", Integer.class))).all().collectList();
        Mono<List<Match>> bracket = includeMatches
                ? matches.findByChampionshipIdOrderByRoundAscPositionAsc(c.id()).map(this::matchView).collectList()
                : Mono.just(List.of());
        return Mono.zip(people, bracket).map(t -> new View(c.id(), c.code(), c.name(), c.gameType(), c.size(),
                c.visibility(), c.scheduledAt(), c.creatorId(), c.status(), c.currentRound(), c.championId(),
                t.getT1().size(), includePeople ? t.getT1() : List.of(), t.getT2(),
                "https://playhuud.com/championships/" + c.code()));
    }

    private Match matchView(ChampionshipMatchRow m) {
        Instant now = Instant.now();
        return new Match(m.id(), m.round(), m.position(), m.playerA(), m.playerB(), m.winnerId(),
                m.status(), m.roomId(), m.gameNumber(), remaining(m.aRemainingMs(), m.aAbsentSince(), now),
                remaining(m.bRemainingMs(), m.bAbsentSince(), now));
    }

    private Mono<Boolean> isParticipant(UUID id, UUID user) {
        return db.sql("SELECT EXISTS(SELECT 1 FROM championship_participants WHERE championship_id=:c AND user_id=:u) AS joined")
                .bind("c", id).bind("u", user).map((r, m) -> Boolean.TRUE.equals(r.get("joined", Boolean.class))).one();
    }

    public Mono<View> startNow(UUID id, UUID creator) {
        return championships.findById(id)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("championship not found")))
                .flatMap(c -> {
                    if (!c.creatorId().equals(creator))
                        return Mono.error(ApiExceptions.forbidden("only the creator can start this championship"));
                    return start(c, true).flatMap(started -> started
                            ? detail(id, creator)
                            : Mono.error(ApiExceptions.conflict("the championship must be in the lobby with every slot filled")));
                });
    }

    private Mono<Void> tryStart(ChampionshipRow c) {
        return start(c, false).then();
    }

    private Mono<Boolean> start(ChampionshipRow c, boolean manual) {
        return db.sql("UPDATE championships SET status='running',current_round=1 WHERE id=:id AND status='lobby' "
                        + "AND (:manual OR scheduled_at<=now()) "
                        + "AND size=(SELECT count(*) FROM championship_participants WHERE championship_id=:id)")
                .bind("id", c.id()).bind("manual", manual).fetch().rowsUpdated()
                .flatMap(n -> n == 0 ? Mono.just(false) : ensureRound(c.id(), 1).thenReturn(true));
    }

    private Mono<Void> ensureRound(UUID id, int round) {
        Mono<List<UUID>> entrants = round == 1
                ? db.sql("SELECT user_id FROM championship_participants WHERE championship_id=:c ORDER BY slot")
                    .bind("c", id).map((r, m) -> r.get("user_id", UUID.class)).all().collectList()
                : matches.findByChampionshipIdAndRoundOrderByPositionAsc(id, round - 1).collectList()
                    .map(previous -> previous.stream().map(ChampionshipMatchRow::winnerId).toList());
        return entrants.flatMap(players -> {
            if (players.size() < 2 || players.size() % 2 != 0) return Mono.empty();
            List<Mono<Long>> inserts = new ArrayList<>();
            for (int i = 0; i < players.size(); i += 2)
                inserts.add(insertMatch(id, round, i / 2 + 1, players.get(i), players.get(i + 1)));
            if (round == 1) {
                int positions = players.size() / 4;
                for (int upcoming = 2; positions >= 1; upcoming++, positions /= 2)
                    for (int position = 1; position <= positions; position++)
                        inserts.add(insertPlaceholder(id, upcoming, position));
            }
            return Flux.concat(inserts).then(activateRound(id, round));
        });
    }

    private Mono<Long> insertPlaceholder(UUID id, int round, int position) {
        return db.sql("INSERT INTO championship_matches(championship_id,round,position) "
                        + "VALUES(:c,:round,:position) ON CONFLICT(championship_id,round,position) DO NOTHING")
                .bind("c", id).bind("round", round).bind("position", position).fetch().rowsUpdated();
    }

    private Mono<Long> insertMatch(UUID id, int round, int position, UUID a, UUID b) {
        var spec = db.sql("INSERT INTO championship_matches(championship_id,round,position,player_a,player_b) "
                        + "VALUES(:c,:round,:position,:a,:b) ON CONFLICT(championship_id,round,position) "
                        + "DO UPDATE SET player_a=EXCLUDED.player_a,player_b=EXCLUDED.player_b "
                        + "WHERE championship_matches.status='pending' AND championship_matches.room_id IS NULL")
                .bind("c", id).bind("round", round).bind("position", position);
        spec = a == null ? spec.bindNull("a", UUID.class) : spec.bind("a", a);
        spec = b == null ? spec.bindNull("b", UUID.class) : spec.bind("b", b);
        return spec.fetch().rowsUpdated();
    }

    private Mono<Void> activateRound(UUID id, int round) {
        return matches.findByChampionshipIdAndRoundOrderByPositionAsc(id, round)
                .filter(m -> "pending".equals(m.status()))
                .flatMap(m -> {
                    if (m.playerA() == null || m.playerB() == null) {
                        UUID winner = m.playerA() == null ? m.playerB() : m.playerA();
                        return completeWithoutGame(m, winner, winner == null ? "no_winner" : "bye");
                    }
                    return createMatchRoom(m);
                }, 16).then();
    }

    private Mono<Void> createMatchRoom(ChampionshipMatchRow m) {
        if (m.roomId() != null) return games.getObject().startTournamentRoom(m.roomId());
        return rooms.save(RoomRow.create(code(), null, m.playerA(), "draughts", 0, null, true))
                .flatMap(room -> members.save(RoomMemberRow.of(room.id(), m.playerA(), null))
                        .then(members.save(RoomMemberRow.of(room.id(), m.playerB(), null)))
                        .then(db.sql("UPDATE championship_matches SET room_id=:room,status='active',started_at=now(), "
                                        + "a_absent_since=now(),b_absent_since=now(),clock_phase=NULL,clock_remaining_ms=NULL "
                                        + "WHERE id=:id AND status='pending'")
                                .bind("room", room.id()).bind("id", m.id()).fetch().rowsUpdated())
                        .flatMap(n -> n == 0 ? Mono.empty() : games.getObject().startTournamentRoom(room.id())
                                .then(syncPause(room.id()))));
    }

    /** Called by the game adapter after persisting a server-computed result. */
    public Mono<Void> gameFinished(UUID roomId, UUID sessionId, Map<String, String> outcome) {
        return matches.findByRoomId(roomId).flatMap(m -> {
            if (!"active".equals(m.status())) return Mono.empty();
            UUID winner = "won".equals(outcome.get(String.valueOf(m.playerA()))) ? m.playerA()
                    : "won".equals(outcome.get(String.valueOf(m.playerB()))) ? m.playerB() : null;
            String result = winner == null ? "draw" : "win";
            var insert = db.sql("INSERT INTO championship_games(game_session_id,match_id,room_id,game_number,outcome,winner_id) "
                            + "VALUES(:session,:match,:room,:number,:outcome,:winner) ON CONFLICT DO NOTHING")
                    .bind("session", sessionId).bind("match", m.id()).bind("room", roomId)
                    .bind("number", m.gameNumber()).bind("outcome", result);
            insert = winner == null ? insert.bindNull("winner", UUID.class) : insert.bind("winner", winner);
            return insert.fetch().rowsUpdated().flatMap(n -> {
                if (winner == null) {
                    // A draw replays the same pairing, not a fresh one — the reconnect
                    // allowance is scoped to the whole pairing ("the server accounts for
                    // time already used during that pairing", not per game), so a_remaining_ms/
                    // b_remaining_ms deliberately carry over unchanged into the next game.
                    return db.sql("UPDATE championship_matches SET status='pending',room_id=NULL,game_number=game_number+1, "
                                    + "a_absent_since=NULL,b_absent_since=NULL, "
                                    + "clock_phase=NULL,clock_remaining_ms=NULL "
                                    + "WHERE id=:id AND room_id=:room AND status='active'")
                            .bind("id", m.id()).bind("room", roomId).fetch().rowsUpdated()
                            .flatMap(updated -> updated == 0 ? Mono.empty() : activateRound(m.championshipId(), m.round()));
                }
                return completeWithoutGame(m, winner, "completed");
            });
        });
    }

    private Mono<Void> completeWithoutGame(ChampionshipMatchRow m, UUID winner, String status) {
        var spec = db.sql("UPDATE championship_matches SET status=:status,winner_id=:winner,completed_at=now(), "
                        + "a_absent_since=NULL,b_absent_since=NULL WHERE id=:id AND status IN ('active','pending')")
                .bind("status", status).bind("id", m.id());
        spec = winner == null ? spec.bindNull("winner", UUID.class) : spec.bind("winner", winner);
        return spec.fetch().rowsUpdated().flatMap(n -> n == 0 ? Mono.empty() : advanceIfRoundDone(m.championshipId(), m.round()));
    }

    private Mono<Void> advanceIfRoundDone(UUID id, int round) {
        return matches.findByChampionshipIdAndRoundOrderByPositionAsc(id, round).collectList()
                .flatMap(done -> {
                    if (done.isEmpty() || done.stream().anyMatch(m -> "active".equals(m.status()) || "pending".equals(m.status())))
                        return Mono.empty();
                    if (done.size() == 1) {
                        UUID champion = done.get(0).winnerId();
                        var spec = db.sql("UPDATE championships SET status='completed',completed_at=now(),champion_id=:champion "
                                        + "WHERE id=:id AND status='running'").bind("id", id);
                        spec = champion == null ? spec.bindNull("champion", UUID.class) : spec.bind("champion", champion);
                        return spec.fetch().rowsUpdated().flatMap(n -> champion == null || n == 0 ? Mono.empty()
                                : db.sql("INSERT INTO championship_badges(championship_id,user_id) VALUES(:c,:u) ON CONFLICT DO NOTHING")
                                        .bind("c", id).bind("u", champion).fetch().rowsUpdated().then());
                    }
                    int next = round + 1;
                    return db.sql("UPDATE championships SET current_round=:round WHERE id=:id AND current_round=:previous")
                            .bind("round", next).bind("id", id).bind("previous", round).fetch().rowsUpdated()
                            .flatMap(n -> {
                                if (n == 0) return Mono.empty();
                                return ensureRound(id, next);
                            });
                });
    }

    public Mono<Void> endBothAbsent(UUID matchId, UUID admin) {
        return matches.findById(matchId).switchIfEmpty(Mono.error(ApiExceptions.notFound("pairing not found")))
                .flatMap(m -> championships.findById(m.championshipId()).flatMap(c -> {
                    if (!c.creatorId().equals(admin)) return Mono.error(ApiExceptions.forbidden("only the creator can end this pairing"));
                    Instant now = Instant.now();
                    if (!"active".equals(m.status()) || remaining(m.aRemainingMs(), m.aAbsentSince(), now) > 0
                            || remaining(m.bRemainingMs(), m.bAbsentSince(), now) > 0
                            || m.aAbsentSince() == null || m.bAbsentSince() == null)
                        return Mono.error(ApiExceptions.conflict("both reconnect allowances must expire first"));
                    return db.sql("UPDATE championship_matches SET status='no_winner',winner_id=NULL,completed_at=now() "
                                    + "WHERE id=:id AND status='active' AND a_absent_since IS NOT NULL "
                                    + "AND b_absent_since IS NOT NULL AND "
                                    + "a_remaining_ms <= EXTRACT(EPOCH FROM (now()-a_absent_since))*1000 "
                                    + "AND b_remaining_ms <= EXTRACT(EPOCH FROM (now()-b_absent_since))*1000")
                            .bind("id", m.id()).fetch().rowsUpdated()
                            .flatMap(n -> n == 0 ? Mono.error(ApiExceptions.conflict("the pairing changed; reload it"))
                                    : advanceIfRoundDone(m.championshipId(), m.round())
                                            .then(games.getObject().closeTournamentRoom(m.roomId())));
                }));
    }

    public Mono<Boolean> forfeitAllowed(UUID roomId, UUID loser) {
        return matches.findByRoomId(roomId).map(m -> {
            if (!"active".equals(m.status())) return false;
            Instant now = Instant.now();
            boolean loserExpired = loser.equals(m.playerA())
                    ? m.aAbsentSince() != null && remaining(m.aRemainingMs(), m.aAbsentSince(), now) == 0
                    : loser.equals(m.playerB()) && m.bAbsentSince() != null
                        && remaining(m.bRemainingMs(), m.bAbsentSince(), now) == 0;
            boolean otherExpired = loser.equals(m.playerA())
                    ? m.bAbsentSince() != null && remaining(m.bRemainingMs(), m.bAbsentSince(), now) == 0
                    : m.aAbsentSince() != null && remaining(m.aRemainingMs(), m.aAbsentSince(), now) == 0;
            return loserExpired && !otherExpired;
        }).defaultIfEmpty(false);
    }

    /** Connection events account for cumulative absence, including the no-show at match start. */
    public Mono<Void> connection(UUID roomId, UUID user, boolean connected) {
        return matches.findByRoomId(roomId).filter(m -> "active".equals(m.status()))
                .flatMap(m -> {
                    String side = user.equals(m.playerA()) ? "a" : user.equals(m.playerB()) ? "b" : null;
                    if (side == null) return Mono.empty();
                    String sql = connected
                            ? "UPDATE championship_matches SET " + side + "_remaining_ms=CASE WHEN " + side
                                    + "_absent_since IS NULL THEN " + side + "_remaining_ms ELSE GREATEST(0," + side
                                    + "_remaining_ms-(EXTRACT(EPOCH FROM (now()-" + side + "_absent_since))*1000)::bigint) END, "
                                    + side + "_absent_since=CASE WHEN " + side + "_absent_since IS NULL OR " + side
                                    + "_remaining_ms>(EXTRACT(EPOCH FROM (now()-" + side + "_absent_since))*1000)::bigint "
                                    + "THEN NULL ELSE " + side + "_absent_since END WHERE id=:id AND status='active'"
                            : "UPDATE championship_matches SET " + side + "_absent_since=COALESCE(" + side
                                    + "_absent_since,now()) WHERE id=:id AND status='active'";
                    return db.sql(sql).bind("id", m.id()).fetch().rowsUpdated()
                            .then(syncPause(roomId)).then(broadcastReconnect(roomId));
                });
    }

    public Mono<Map<String, Object>> reconnectStatus(UUID roomId) {
        return matches.findByRoomId(roomId).map(m -> {
            List<Map<String, Object>> missing = new ArrayList<>();
            Instant now = Instant.now();
            if ("active".equals(m.status())) {
                if (m.aAbsentSince() != null) missing.add(Map.of("userId", m.playerA().toString(),
                        "secondsLeft", (remaining(m.aRemainingMs(), m.aAbsentSince(), now) + 999) / 1000));
                if (m.bAbsentSince() != null) missing.add(Map.of("userId", m.playerB().toString(),
                        "secondsLeft", (remaining(m.bRemainingMs(), m.bAbsentSince(), now) + 999) / 1000));
            }
            return Map.<String, Object>of("missing", missing);
        }).defaultIfEmpty(Map.of("missing", List.of()));
    }

    private Mono<Void> broadcastReconnect(UUID roomId) {
        return reconnectStatus(roomId).doOnNext(status -> runtimes.find(roomId)
                .ifPresent(rt -> rt.bus.tryEmitNext(new LobbyBroadcast("RECONNECT_WAIT", status)))).then();
    }

    private Mono<Void> syncPause(UUID roomId) {
        return matches.findByRoomId(roomId).flatMap(m -> {
            if (!"active".equals(m.status())) return Mono.empty();
            boolean paused = m.aAbsentSince() != null || m.bAbsentSince() != null;
            return games.getObject().setTournamentPaused(roomId, paused);
        });
    }

    public Mono<Boolean> spectatorAllowed(UUID roomId, UUID user) {
        return matches.findByRoomId(roomId)
                .flatMap(m -> championships.findById(m.championshipId())
                        .flatMap(c -> "public".equals(c.visibility()) ? Mono.just(true) : isParticipant(c.id(), user)))
                .defaultIfEmpty(true);
    }

    public Mono<Boolean> isTournamentRoom(UUID roomId) {
        return matches.findByRoomId(roomId).hasElement();
    }

    public record SavedClock(String phase, long remainingMs) {}

    public Mono<Void> recordClock(UUID roomId, String phase, long remainingMs) {
        return db.sql("UPDATE championship_matches SET clock_phase=:phase,clock_remaining_ms=:remaining "
                        + "WHERE room_id=:room AND status='active'")
                .bind("phase", phase).bind("remaining", Math.max(0, remainingMs))
                .bind("room", roomId).fetch().rowsUpdated().then();
    }

    public Mono<SavedClock> savedClock(UUID roomId) {
        return db.sql("SELECT clock_phase,clock_remaining_ms FROM championship_matches WHERE room_id=:room "
                        + "AND clock_phase IS NOT NULL AND clock_remaining_ms IS NOT NULL")
                .bind("room", roomId)
                .map((r, m) -> new SavedClock(r.get("clock_phase", String.class),
                        r.get("clock_remaining_ms", Long.class))).one();
    }

    public record SavedAction(String actionId, UUID actor, String type, String payload) {}

    public Mono<Void> recordAction(UUID roomId, UUID sessionId, String actionId, UUID actor,
                                   String type, String payload) {
        return matches.findByRoomId(roomId).filter(m -> "active".equals(m.status()))
                .flatMap(m -> {
                    var insert = db.sql("INSERT INTO championship_actions(game_session_id,action_id,actor_id,action_type,payload) "
                                    + "VALUES(:session,:action,:actor,:type,:payload) ON CONFLICT DO NOTHING")
                            .bind("session", sessionId).bind("action", actionId)
                            .bind("type", type).bind("payload", payload);
                    insert = actor == null ? insert.bindNull("actor", UUID.class) : insert.bind("actor", actor);
                    return insert.fetch().rowsUpdated();
                }).then();
    }

    public Flux<SavedAction> savedActions(UUID sessionId) {
        return db.sql("SELECT action_id,actor_id,action_type,payload FROM championship_actions "
                        + "WHERE game_session_id=:s ORDER BY sequence")
                .bind("s", sessionId)
                .map((r, m) -> new SavedAction(r.get("action_id", String.class), r.get("actor_id", UUID.class),
                        r.get("action_type", String.class), r.get("payload", String.class))).all();
    }

    @Scheduled(fixedDelay = 5000)
    public void tick() {
        championships.findAll()
                .filter(c -> "lobby".equals(c.status()) && !c.scheduledAt().isAfter(Instant.now()))
                .concatMap(this::tryStart)
                .thenMany(championships.findAll().filter(c -> "running".equals(c.status())))
                .concatMap(c -> recover(c).onErrorResume(e -> { log.warn("championship recovery failed {}: {}", c.id(), e.toString()); return Mono.empty(); }))
                .thenMany(db.sql("SELECT id,room_id,player_a,player_b,a_remaining_ms,b_remaining_ms,a_absent_since,b_absent_since "
                                + "FROM championship_matches WHERE status='active' AND room_id IS NOT NULL")
                        .map((r, meta) -> new Absence(r.get("id", UUID.class), r.get("room_id", UUID.class),
                                r.get("player_a", UUID.class), r.get("player_b", UUID.class),
                                r.get("a_remaining_ms", Long.class), r.get("b_remaining_ms", Long.class),
                                r.get("a_absent_since", Instant.class), r.get("b_absent_since", Instant.class))).all())
                .concatMap(a -> checkForfeit(a).then(games.getObject().persistTournamentClock(a.roomId())))
                .then(reconcileBadges())
                .subscribe(null, e -> log.warn("championship tick failed: {}", e.toString()));
    }

    private Mono<Void> reconcileBadges() {
        return db.sql("INSERT INTO championship_badges(championship_id,user_id) "
                        + "SELECT id,champion_id FROM championships WHERE status='completed' AND champion_id IS NOT NULL "
                        + "ON CONFLICT DO NOTHING")
                .fetch().rowsUpdated().then();
    }

    private Mono<Void> recover(ChampionshipRow c) {
        Mono<Void> bracket = ensureRound(c.id(), c.currentRound())
                .then(advanceIfRoundDone(c.id(), c.currentRound()));
        return bracket.thenMany(matches.findByChampionshipIdAndRoundOrderByPositionAsc(c.id(), c.currentRound())
                        .filter(m -> "active".equals(m.status()) && m.roomId() != null))
                .concatMap(m -> {
                    return reconcileCompletedGame(m).then(matches.findById(m.id())
                            .filter(fresh -> "active".equals(fresh.status()))
                            .flatMap(fresh -> {
                                var existing = runtimes.find(fresh.roomId());
                                if (existing.map(RoomRuntime::started).orElse(false)) return Mono.empty();
                                if (existing.isPresent()) return games.getObject().startTournamentRoom(fresh.roomId())
                                        .then(syncPause(fresh.roomId()));
                                return db.sql("UPDATE championship_matches SET a_absent_since=COALESCE(a_absent_since,now()), "
                                                + "b_absent_since=COALESCE(b_absent_since,now()) WHERE id=:id")
                                        .bind("id", fresh.id()).fetch().rowsUpdated()
                                        .then(games.getObject().startTournamentRoom(fresh.roomId()));
                            }));
                }).then();
    }

    private Mono<Void> reconcileCompletedGame(ChampionshipMatchRow m) {
        return db.sql("SELECT s.id AS session_id,g.per_player_outcome::text AS outcome FROM game_sessions s "
                        + "JOIN game_results g ON g.game_session_id=s.id WHERE s.room_id=:room "
                        + "ORDER BY s.started_at DESC LIMIT 1")
                .bind("room", m.roomId())
                .map((r, meta) -> Map.entry(r.get("session_id", UUID.class), r.get("outcome", String.class))).one()
                .flatMap(result -> Mono.fromCallable(() -> {
                    @SuppressWarnings("unchecked")
                    Map<String, String> outcome = new com.fasterxml.jackson.databind.ObjectMapper()
                            .readValue(result.getValue(), Map.class);
                    return outcome;
                }).flatMap(outcome -> gameFinished(m.roomId(), result.getKey(), outcome)))
                .then();
    }

    private record Absence(UUID id, UUID roomId, UUID a, UUID b, long aMs, long bMs,
                           Instant aSince, Instant bSince) {}

    private Mono<Void> checkForfeit(Absence a) {
        Instant now = Instant.now();
        boolean aExpired = a.aSince() != null && remaining(a.aMs(), a.aSince(), now) == 0;
        boolean bExpired = a.bSince() != null && remaining(a.bMs(), a.bSince(), now) == 0;
        if (aExpired == bExpired) return Mono.empty(); // both absent: creator decision; neither: wait
        return games.getObject().forfeitTournamentRoom(a.roomId(), aExpired ? a.a() : a.b());
    }

    private static long remaining(long bank, Instant since, Instant now) {
        return since == null ? bank : Math.max(0, bank - Math.max(0, Duration.between(since, now).toMillis()));
    }

    private static String code() {
        StringBuilder s = new StringBuilder(8);
        for (int i = 0; i < 8; i++) s.append(ALPHABET.charAt(RNG.nextInt(ALPHABET.length())));
        return s.toString();
    }
}
