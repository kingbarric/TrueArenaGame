package app.truearena.api.huudspace;

import app.truearena.api.huud.HuudService;
import app.truearena.api.huudspace.HuudSpaceDtos.Moment;
import app.truearena.api.huudspace.HuudSpaceDtos.Person;
import app.truearena.engine.GameEvent;
import app.truearena.room.RoomEventLog;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * What's going on in a Live Huud, for its card on the Live tab: the game on
 * now, told move by move from its public log, then who won, who walked in,
 * who went Live — and, for the Huud's own members only, the chat. Best
 * effort: a card without moments is still a card, so nothing here can fail
 * the Live list.
 */
@Service
public class HuudMoments {

    static final int MAX = 3;
    private static final int GAME_LINES = 2;
    private static final int LOG_WINDOW = 40;
    private static final int CHAT_LENGTH = 120;
    private static final Set<String> SIDED = Set.of("chess", "draughts");
    private static final Logger log = LoggerFactory.getLogger(HuudMoments.class);

    private final DatabaseClient db;
    private final RoomEventLog events;
    private final ObjectMapper mapper;

    public HuudMoments(DatabaseClient db, RoomEventLog events, ObjectMapper mapper) {
        this.db = db;
        this.events = events;
        this.mapper = mapper;
    }

    /** Newest first; the game's own lines lead while it's being played. */
    public Mono<List<Moment>> forCard(UUID huud, UUID roomId, String gameType, boolean playing, UUID viewer, boolean member) {
        Mono<List<Moment>> game = playing && roomId != null ? play(roomId, gameType, viewer) : Mono.just(List.of());
        return Mono.zip(game, social(huud, viewer, member))
                .map(t -> {
                    List<Moment> all = new ArrayList<>(t.getT1());
                    all.addAll(t.getT2());
                    return all.size() > MAX ? List.copyOf(all.subList(0, MAX)) : List.copyOf(all);
                })
                .onErrorResume(e -> {
                    log.debug("moments for Huud {} unavailable: {}", huud, e.toString());
                    return Mono.just(List.of());
                });
    }

    private Mono<List<Moment>> play(UUID roomId, String gameType, UUID viewer) {
        Mono<Map<String, String>> sides = SIDED.contains(gameType)
                ? events.first(roomId).flatMap(this::parse).map(opening -> HuudMomentText.sides(gameType, opening))
                        .defaultIfEmpty(Map.of())
                : Mono.just(Map.of());
        return Mono.zip(events.latest(roomId, LOG_WINDOW).concatMap(this::parse).collectList(), sides)
                .flatMap(t -> {
                    List<HuudMomentText.Line> lines = HuudMomentText.pick(gameType, t.getT1(), t.getT2(), GAME_LINES);
                    if (lines.isEmpty()) return Mono.just(List.<Moment>of());
                    Set<UUID> ids = new LinkedHashSet<>();
                    for (HuudMomentText.Line line : lines) {
                        addId(ids, line.actor());
                        line.mentions().forEach(m -> addId(ids, m));
                    }
                    return people(ids, viewer).map(byId -> {
                        List<Moment> out = new ArrayList<>();
                        for (HuudMomentText.Line line : lines) {
                            Person who = line.actor() == null ? null : byId.get(line.actor());
                            // A player we can't name — a blocked one, or one gone — leaves no line.
                            if (line.actor() != null && who == null) continue;
                            String text = line.text();
                            for (int i = 0; i < line.mentions().size(); i++) {
                                Person other = byId.get(line.mentions().get(i));
                                text = text.replace("{" + i + "}", other == null ? "someone" : other.username());
                            }
                            out.add(new Moment("play", who, text, null));
                        }
                        return out;
                    });
                });
    }

    private Mono<List<Moment>> social(UUID huud, UUID viewer, boolean member) {
        String chat = member
                ? "UNION ALL SELECT 'chat', c.created_at, c.user_id, c.body FROM huud_space_messages c "
                + "WHERE c.huud_space_id=:id AND c.created_at > now()-interval '30 minutes' "
                : "";
        return db.sql("SELECT e.kind, e.at, e.extra, u.id, u.display_name, u.username, u.avatar_url, a.avatar_id, a.outfit_id FROM ("
                        + "SELECT 'win' AS kind, mr.completed_at AS at, mp.user_id, mr.game_type AS extra FROM match_records mr "
                        + "JOIN rooms r ON r.id=mr.room_id JOIN huud_spaces s ON s.id=r.huud_space_id "
                        + "JOIN match_participants mp ON mp.match_id=mr.id AND mp.outcome='won' "
                        + "WHERE r.huud_space_id=:id AND mr.completed_at >= s.live_since "
                        + "UNION ALL SELECT 'joined', m.live_at, m.user_id, NULL FROM huud_space_members m "
                        + "JOIN huud_spaces s ON s.id=m.huud_space_id WHERE m.huud_space_id=:id AND m.live_at IS NOT NULL "
                        + "AND m.user_id<>s.created_by AND m.live_at > now()-interval '30 minutes' "
                        + "UNION ALL SELECT 'live', s.live_since, s.created_by, NULL FROM huud_spaces s "
                        + "WHERE s.id=:id AND s.live_since > now()-interval '2 hours' "
                        + chat
                        + ") e JOIN users u ON u.id=e.user_id LEFT JOIN user_huud_avatars a ON a.user_id=u.id "
                        + "WHERE NOT " + HuudSpaceService.blockedSql("u.id", ":viewer") + " "
                        + "ORDER BY e.at DESC LIMIT " + MAX)
                .bind("id", huud).bind("viewer", viewer)
                .map((r, m) -> {
                    String kind = r.get("kind", String.class);
                    String extra = r.get("extra", String.class);
                    String text = switch (kind) {
                        case "win" -> "won " + HuudService.GAME_NAMES.getOrDefault(extra, "a game");
                        case "joined" -> "joined";
                        case "live" -> "went Live";
                        default -> clip(extra);
                    };
                    return new Moment(kind, person(r.get("id", UUID.class), r.get("display_name", String.class),
                            r.get("username", String.class), r.get("avatar_url", String.class),
                            r.get("avatar_id", String.class), r.get("outfit_id", String.class)),
                            text, HuudSpaceService.instant(r.get("at")));
                })
                .all().collectList();
    }

    /** The players a game line names, as the viewer may see them — nobody either side has blocked. */
    private Mono<Map<String, Person>> people(Set<UUID> ids, UUID viewer) {
        if (ids.isEmpty()) return Mono.just(Map.of());
        return db.sql("SELECT u.id, u.display_name, u.username, u.avatar_url, a.avatar_id, a.outfit_id FROM users u "
                        + "LEFT JOIN user_huud_avatars a ON a.user_id=u.id "
                        + "WHERE u.id = ANY(:ids) AND NOT " + HuudSpaceService.blockedSql("u.id", ":viewer"))
                .bind("ids", ids.toArray(UUID[]::new)).bind("viewer", viewer)
                .map((r, m) -> person(r.get("id", UUID.class), r.get("display_name", String.class),
                        r.get("username", String.class), r.get("avatar_url", String.class),
                        r.get("avatar_id", String.class), r.get("outfit_id", String.class)))
                .all()
                .collectMap(p -> p.userId().toString(), p -> p, HashMap::new)
                .map(Map::copyOf);
    }

    private Mono<GameEvent> parse(String json) {
        return Mono.fromCallable(() -> mapper.readValue(json, GameEvent.class)).onErrorResume(e -> Mono.empty());
    }

    private static Person person(UUID id, String displayName, String username, String avatarUrl,
                                 String avatarId, String outfitId) {
        return new Person(id, displayName, username, avatarUrl, false, false, false, null, false, avatarId, outfitId);
    }

    private static void addId(Set<UUID> ids, String raw) {
        if (raw == null) return;
        try {
            ids.add(UUID.fromString(raw));
        } catch (IllegalArgumentException ignored) {
            // Not a person (a team name, a stale id) — the line just won't name them.
        }
    }

    private static String clip(String body) {
        String text = body == null ? "" : body.strip().replaceAll("\\s+", " ");
        return text.length() > CHAT_LENGTH ? text.substring(0, CHAT_LENGTH - 1).strip() + "…" : text;
    }
}
