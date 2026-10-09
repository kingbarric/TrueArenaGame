package app.truearena.api.huud;

import app.truearena.api.huud.HuudDtos.CreateChallengeRequest;
import app.truearena.api.huud.HuudDtos.CreatePostRequest;
import app.truearena.api.huud.HuudDtos.CreatedPost;
import app.truearena.api.huud.HuudDtos.FeedItem;
import app.truearena.api.huud.HuudDtos.Filter;
import app.truearena.api.huud.HuudDtos.OpenGame;
import app.truearena.api.huud.HuudDtos.PersonView;
import app.truearena.api.huud.HuudDtos.Tab;
import app.truearena.api.huud.HuudDtos.Tournament;
import app.truearena.api.huud.HuudDtos.Win;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.push.PushNotificationService;
import app.truearena.api.room.RoomDtos.RoomView;
import app.truearena.api.room.RoomService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.UserRepository;
import io.r2dbc.spi.Row;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * The Huud feed — "Your Huud" (you and your friends) and "For you" (the whole
 * public lobby).
 *
 * <p>Four sources, merged newest first:
 * <ul>
 *   <li>open game requests and challenges — {@code huud_posts}, each backed by
 *       a real lobby room;</li>
 *   <li>wins — straight from {@code match_records}, so every win card is
 *       verified by construction;</li>
 *   <li>tournaments open for registration — {@code championships};</li>
 *   <li>freshly crowned champions — {@code championships.champion_id}.</li>
 * </ul>
 *
 * <p>Your Huud is scoped to you and your accepted friends, and is the only
 * place a challenge shows (to its two players). For you is the public lobby:
 * anyone's open request, public championships, and wins worth surfacing —
 * ranked, or a streak of three or more — from players whose profile is public.
 */
@Service
public class HuudService {

    static final Duration REQUEST_TTL = Duration.ofMinutes(15);
    static final Duration CHALLENGE_TTL = Duration.ofMinutes(10);
    static final int PAGE = 40;

    /** Players a request gathers when the author doesn't say — the game's natural table. */
    static final Map<String, Integer> DEFAULT_SEATS = Map.of(
            "draughts", 2, "chess", 2, "goosi", 2,
            "whot", 4, "ludo", 4, "wordbluff", 4, "truearena", 6);
    private static final Set<String> HEAD_TO_HEAD = Set.of("draughts", "chess", "goosi");

    static final Map<String, String> GAME_NAMES = Map.of(
            "draughts", "Draughts", "chess", "Chess", "goosi", "Macala", "whot", "Whot",
            "ludo", "Ludo", "wordbluff", "Word Bluff", "truearena", "Traitors");

    private final DatabaseClient db;
    private final RoomService rooms;
    private final UserRepository users;
    private final InboxRegistry inbox;
    private final PushNotificationService push;

    @org.springframework.beans.factory.annotation.Autowired(required = false)
    private FeedPostService posts;

    public HuudService(DatabaseClient db, RoomService rooms, UserRepository users, InboxRegistry inbox,
                       PushNotificationService push) {
        this.db = db;
        this.rooms = rooms;
        this.users = users;
        this.inbox = inbox;
        this.push = push;
    }

    // ---------------------------------------------------------------- reading

    public Flux<FeedItem> feed(UUID viewer, Tab tab, Filter filter) {
        List<Flux<FeedItem>> sources = new ArrayList<>();
        if (filter == Filter.ALL || filter == Filter.OPEN) {
            sources.add(openGames(viewer, tab));
            sources.add(sharedHuuds(viewer, tab));
        }
        if (filter == Filter.ALL || filter == Filter.WINS) {
            sources.add(wins(viewer, tab));
        }
        if (filter == Filter.ALL || filter == Filter.TOURNAMENTS) {
            sources.add(tournaments(viewer, tab));
        }
        if (filter != Filter.OPEN) {
            sources.add(champions(viewer, tab));
        }
        if (filter == Filter.ALL && tab == Tab.FRIENDS && posts != null) {
            sources.add(posts.friendsPosts(viewer, PAGE));
        }
        return Flux.merge(sources)
                .collectSortedList(feedOrder(viewer))
                .flatMapIterable(items -> items.size() > PAGE ? items.subList(0, PAGE) : items);
    }

    /** A challenge waiting on the viewer goes to the top; everything else newest first. */
    static Comparator<FeedItem> feedOrder(UUID viewer) {
        Comparator<FeedItem> waitingOnMe = Comparator.comparing(item -> !isWaitingOn(item, viewer));
        return waitingOnMe.thenComparing(FeedItem::at, Comparator.reverseOrder());
    }

    private static boolean isWaitingOn(FeedItem item, UUID viewer) {
        return "challenge".equals(item.kind()) && item.game() != null && item.game().target() != null
                && viewer.equals(item.game().target().userId());
    }

    /** True when {@code column} is one of the viewer's accepted friends. Binds {@code :uid}. */
    private static String friendOf(String column) {
        return "EXISTS (SELECT 1 FROM friends f WHERE f.status = 'accepted'"
                + " AND f.low_user_id = LEAST(:uid, " + column + ")"
                + " AND f.high_user_id = GREATEST(:uid, " + column + "))";
    }

    /**
     * Huuds their hosts shared. Friends: your own, your friends' and ones
     * you're in (whatever the privacy — a private one says "Ask to join").
     * For you: public ones. Never from someone either of you blocked.
     */
    private Flux<FeedItem> sharedHuuds(UUID viewer, Tab tab) {
        String scope = tab == Tab.FRIENDS
                ? "(s.created_by = :uid OR " + friendOf("s.created_by") + " OR me.user_id IS NOT NULL)"
                : "s.privacy = 'public'";
        return db.sql("SELECT s.id, s.name, s.privacy, s.feed_message, s.shared_at, s.created_by AS owner_id, "
                        + "u.display_name, u.username, u.avatar_url, r.game_type, r.status AS room_status, "
                        + "(SELECT count(*) FROM room_members rm WHERE rm.room_id = r.id) AS players, "
                        + "(SELECT count(*) FROM huud_space_members c WHERE c.huud_space_id = s.id AND c.live_at IS NOT NULL) AS people, "
                        + "(me.user_id IS NOT NULL) AS mine, " + friendOf("s.created_by") + " AS friend "
                        + "FROM huud_spaces s JOIN users u ON u.id = s.created_by "
                        + "LEFT JOIN rooms r ON r.id = s.current_room_id "
                        + "LEFT JOIN huud_space_members me ON me.huud_space_id = s.id AND me.user_id = :uid AND me.left_at IS NULL "
                        + "WHERE s.status = 'active' AND s.live_since IS NOT NULL AND s.shared_at IS NOT NULL AND " + scope + " "
                        + "AND NOT EXISTS (SELECT 1 FROM huud_space_members x WHERE x.huud_space_id = s.id AND x.user_id = :uid AND x.removed) "
                        + "AND NOT " + app.truearena.api.huudspace.HuudSpaceService.blockedSql("s.created_by", ":uid") + " "
                        + "ORDER BY s.shared_at DESC LIMIT " + PAGE)
                .bind("uid", viewer)
                .map((row, meta) -> {
                    UUID owner = row.get("owner_id", UUID.class);
                    String privacy = row.get("privacy", String.class);
                    boolean mine = Boolean.TRUE.equals(row.get("mine", Boolean.class));
                    boolean friend = Boolean.TRUE.equals(row.get("friend", Boolean.class));
                    String access = mine ? "in"
                            : owner.equals(viewer) || "public".equals(privacy) || ("friends".equals(privacy) && friend)
                            ? "join" : "ask";
                    String gameType = row.get("game_type", String.class);
                    String roomStatus = row.get("room_status", String.class);
                    var huud = new HuudDtos.SharedHuud(row.get("id", UUID.class), row.get("name", String.class), privacy,
                            ((Number) row.get("people")).intValue(),
                            roomStatus == null ? null : app.truearena.api.huudspace.HuudSpaceService.gameStatus(roomStatus),
                            ((Number) row.get("players")).intValue(), seatsFor(gameType), access);
                    var host = new PersonView(owner, row.get("display_name", String.class), row.get("username", String.class),
                            row.get("avatar_url", String.class), friend);
                    return new FeedItem("huud", "huud:" + huud.huudSpaceId(), instant(row.get("shared_at")), host,
                            gameType, row.get("feed_message", String.class), null, null, null, huud);
                })
                .all();
    }

    private static Instant instant(Object value) {
        if (value == null) return null;
        if (value instanceof Instant i) return i;
        return ((java.time.OffsetDateTime) value).toInstant();
    }

    /**
     * One query for the whole section: each post's players come back as
     * parallel arrays and a challenge's last result as a scalar subquery, so
     * a page of 40 cards is one round trip, not 80.
     */
    private Flux<FeedItem> openGames(UUID viewer, Tab tab) {
        String scope = tab == Tab.FRIENDS
                ? "((p.kind = 'challenge' AND (p.target_user_id = :uid OR p.author_id = :uid))"
                        + " OR (p.kind = 'game_request' AND (p.author_id = :uid OR " + friendOf("p.author_id") + ")))"
                : "p.kind = 'game_request'";
        return db.sql("""
                        SELECT p.id, p.kind, p.author_id, p.room_id, p.game_type, p.message, p.ranked, p.seats,
                               p.target_user_id, p.created_at, p.expires_at, r.code, r.status AS room_status,
                               a.display_name AS a_name, a.username AS a_username, a.avatar_url AS a_avatar,
                               %s AS a_friend,
                               t.display_name AS t_name, t.username AS t_username, t.avatar_url AS t_avatar,
                               (t.id IS NOT NULL AND %s) AS t_friend,
                               pl.ids AS player_ids, pl.names AS player_names, pl.usernames AS player_usernames,
                               pl.avatars AS player_avatars, pl.friends AS player_friends,
                               CASE WHEN p.kind = 'challenge' THEN (
                                   SELECT me.outcome FROM match_participants me
                                   JOIN match_participants them ON them.match_id = me.match_id
                                    AND them.user_id = CASE WHEN p.author_id = :uid THEN p.target_user_id ELSE p.author_id END
                                   JOIN match_records mr ON mr.id = me.match_id
                                   WHERE me.user_id = :uid AND mr.game_type = p.game_type
                                   ORDER BY mr.completed_at DESC LIMIT 1) END AS last_outcome
                        FROM huud_posts p
                        JOIN rooms r ON r.id = p.room_id
                        JOIN users a ON a.id = p.author_id
                        LEFT JOIN users t ON t.id = p.target_user_id
                        LEFT JOIN LATERAL (
                            SELECT array_agg(m.user_id ORDER BY m.joined_at) AS ids,
                                   array_agg(u.display_name ORDER BY m.joined_at) AS names,
                                   array_agg(u.username ORDER BY m.joined_at) AS usernames,
                                   array_agg(COALESCE(u.avatar_url, '') ORDER BY m.joined_at) AS avatars,
                                   array_agg(%s ORDER BY m.joined_at) AS friends
                            FROM room_members m JOIN users u ON u.id = m.user_id
                            WHERE m.room_id = p.room_id
                        ) pl ON true
                        -- A full or started game stays up, marked filled, until the post runs out.
                        WHERE p.status = 'open' AND p.expires_at > now() AND r.status IN ('lobby', 'in_game') AND %s
                        ORDER BY p.created_at DESC
                        LIMIT %d
                        """.formatted(friendOf("p.author_id"), friendOf("t.id"), friendOf("m.user_id"), scope, PAGE))
                .bind("uid", viewer)
                .map((row, meta) -> PostRow.of(row).toItem(viewer, playersOf(row), row.get("last_outcome", String.class)))
                .all();
    }

    private static List<PersonView> playersOf(Row row) {
        UUID[] ids = row.get("player_ids", UUID[].class);
        if (ids == null) {
            return List.of();
        }
        String[] names = row.get("player_names", String[].class);
        String[] usernames = row.get("player_usernames", String[].class);
        String[] avatars = row.get("player_avatars", String[].class);
        Boolean[] friends = row.get("player_friends", Boolean[].class);
        List<PersonView> players = new ArrayList<>(ids.length);
        for (int i = 0; i < ids.length; i++) {
            String avatar = avatars[i];
            players.add(new PersonView(ids[i], names[i], usernames[i], avatar == null || avatar.isEmpty() ? null : avatar,
                    Boolean.TRUE.equals(friends[i])));
        }
        return players;
    }

    /**
     * Narrow first, then decorate: pick each player's latest win per game and
     * apply the tab's scope, cut to a page, and only then compute the rating,
     * weekly delta and beaten names for those rows.
     */
    private Flux<FeedItem> wins(UUID viewer, Tab tab) {
        String scope = tab == Tab.FRIENDS
                ? "(l.user_id = :uid OR " + friendOf("l.user_id") + ")"
                : "((l.ranked OR (rec.recent[1] = 'won' AND rec.recent[2] = 'won' AND rec.recent[3] = 'won'))"
                        + " AND (l.user_id = :uid OR " + friendOf("l.user_id") + " OR COALESCE(cp.profile_public, true)))";
        return db.sql("""
                        WITH latest AS (
                            SELECT DISTINCT ON (mp.user_id, mr.game_type)
                                   mp.user_id, mr.id AS match_id, mr.game_type, mr.ranked, mr.completed_at
                            FROM match_records mr
                            JOIN match_participants mp ON mp.match_id = mr.id AND mp.outcome = 'won'
                            WHERE mr.completed_at > now() - interval '48 hours'
                            ORDER BY mp.user_id, mr.game_type, mr.completed_at DESC
                        ), page AS (
                            SELECT l.*, u.display_name, u.username, u.avatar_url, %s AS friend, rec.recent
                            FROM latest l
                            JOIN users u ON u.id = l.user_id
                            LEFT JOIN competitive_profiles cp ON cp.user_id = l.user_id
                            LEFT JOIN LATERAL (
                                SELECT array_agg(x.outcome ORDER BY x.completed_at DESC) AS recent FROM (
                                    SELECT p3.outcome, r3.completed_at FROM match_participants p3
                                    JOIN match_records r3 ON r3.id = p3.match_id
                                    WHERE p3.user_id = l.user_id AND r3.game_type = l.game_type
                                    ORDER BY r3.completed_at DESC LIMIT 20) x
                            ) rec ON true
                            WHERE NOT u.is_bot AND NOT u.is_guest
                              -- a win over Cyber Agents alone isn't news
                              AND EXISTS (SELECT 1 FROM match_participants op JOIN users o ON o.id = op.user_id
                                           WHERE op.match_id = l.match_id AND op.user_id <> l.user_id AND NOT o.is_bot)
                              AND %s
                            ORDER BY l.completed_at DESC
                            LIMIT %d
                        )
                        SELECT page.*,
                               CASE WHEN pgr.rated_games_played > 0 THEN pgr.rating END AS rating,
                               (SELECT SUM(p2.rating_delta) FROM match_participants p2
                                  JOIN match_records r2 ON r2.id = p2.match_id
                                 WHERE p2.user_id = page.user_id AND r2.game_type = page.game_type
                                   AND r2.completed_at > now() - interval '7 days') AS week_delta,
                               ARRAY(SELECT o.display_name FROM match_participants op
                                       JOIN users o ON o.id = op.user_id
                                      WHERE op.match_id = page.match_id AND op.user_id <> page.user_id
                                        AND op.outcome = 'lost' AND NOT o.is_bot
                                      ORDER BY o.display_name) AS beaten
                        FROM page
                        LEFT JOIN player_game_ratings pgr ON pgr.user_id = page.user_id AND pgr.game_type = page.game_type
                        ORDER BY page.completed_at DESC
                        """.formatted(friendOf("l.user_id"), scope, PAGE))
                .bind("uid", viewer)
                .map((row, meta) -> winItem(row))
                .all();
    }

    private static FeedItem winItem(Row row) {
        String[] recentRaw = row.get("recent", String[].class);
        List<String> recent = recentRaw == null ? List.of() : Arrays.asList(recentRaw);
        String[] beaten = row.get("beaten", String[].class);
        UUID matchId = row.get("match_id", UUID.class);
        PersonView actor = new PersonView(row.get("user_id", UUID.class), row.get("display_name", String.class),
                row.get("username", String.class), row.get("avatar_url", String.class),
                Boolean.TRUE.equals(row.get("friend", Boolean.class)));
        Win win = new Win(matchId, Boolean.TRUE.equals(row.get("ranked", Boolean.class)), streakOf(recent),
                recent.size() > 8 ? recent.subList(0, 8) : recent,
                row.get("rating", Double.class), row.get("week_delta", Double.class),
                beaten == null ? List.of() : Arrays.asList(beaten));
        return new FeedItem("win", "win:" + matchId + ":" + actor.userId(), row.get("completed_at", Instant.class),
                actor, row.get("game_type", String.class), null, null, win, null, null);
    }

    /** Wins in a row at the front of a newest-first result list. */
    static int streakOf(List<String> recentNewestFirst) {
        int streak = 0;
        for (String outcome : recentNewestFirst) {
            if (!"won".equals(outcome)) {
                break;
            }
            streak++;
        }
        return streak;
    }

    private Flux<FeedItem> tournaments(UUID viewer, Tab tab) {
        String participant = "EXISTS (SELECT 1 FROM championship_participants cp WHERE cp.championship_id = c.id"
                + " AND (cp.user_id = :uid OR " + friendOf("cp.user_id") + "))";
        String scope = tab == Tab.FRIENDS
                ? "((c.visibility = 'public' AND (c.creator_id = :uid OR " + friendOf("c.creator_id") + " OR " + participant + "))"
                        + " OR EXISTS (SELECT 1 FROM championship_participants me WHERE me.championship_id = c.id AND me.user_id = :uid))"
                : "c.visibility = 'public'";
        return db.sql("""
                        SELECT c.id, c.code, c.name, c.game_type, c.size, c.scheduled_at, c.status, c.created_at,
                               c.creator_id AS person_id, u.display_name, u.username, u.avatar_url,
                               %s AS friend,
                               (SELECT count(*) FROM championship_participants p WHERE p.championship_id = c.id) AS joined,
                               EXISTS (SELECT 1 FROM championship_participants p
                                        WHERE p.championship_id = c.id AND p.user_id = :uid) AS viewer_joined
                        FROM championships c JOIN users u ON u.id = c.creator_id
                        WHERE c.status = 'lobby' AND c.scheduled_at > now() - interval '1 hour' AND %s
                        ORDER BY c.created_at DESC
                        LIMIT 20
                        """.formatted(friendOf("c.creator_id"), scope))
                .bind("uid", viewer)
                .map((row, meta) -> championshipItem(row, "tournament", row.get("created_at", Instant.class), null))
                .all();
    }

    private Flux<FeedItem> champions(UUID viewer, Tab tab) {
        String scope = tab == Tab.FRIENDS
                ? "(c.champion_id = :uid OR " + friendOf("c.champion_id")
                        + " OR EXISTS (SELECT 1 FROM championship_participants me WHERE me.championship_id = c.id AND me.user_id = :uid))"
                : "c.visibility = 'public'";
        return db.sql("""
                        SELECT c.id, c.code, c.name, c.game_type, c.size, c.scheduled_at, c.status, c.completed_at,
                               c.champion_id AS person_id, u.display_name, u.username, u.avatar_url,
                               %s AS friend,
                               (SELECT count(*) FROM championship_participants p WHERE p.championship_id = c.id) AS joined,
                               EXISTS (SELECT 1 FROM championship_participants p
                                        WHERE p.championship_id = c.id AND p.user_id = :uid) AS viewer_joined,
                               (SELECT o.display_name FROM championship_matches m
                                  JOIN users o ON o.id = CASE WHEN m.player_a = c.champion_id THEN m.player_b ELSE m.player_a END
                                 WHERE m.championship_id = c.id AND m.winner_id = c.champion_id
                                 ORDER BY m.round DESC LIMIT 1) AS runner_up
                        FROM championships c JOIN users u ON u.id = c.champion_id
                        WHERE c.status = 'completed' AND c.completed_at > now() - interval '3 days' AND %s
                        ORDER BY c.completed_at DESC
                        LIMIT 20
                        """.formatted(friendOf("c.champion_id"), scope))
                .bind("uid", viewer)
                .map((row, meta) -> {
                    String runnerUp = row.get("runner_up", String.class);
                    return championshipItem(row, "champion", row.get("completed_at", Instant.class),
                            runnerUp == null ? null : "Beat " + runnerUp + " in the final");
                })
                .all();
    }

    private static FeedItem championshipItem(Row row, String kind, Instant at, String message) {
        UUID id = row.get("id", UUID.class);
        PersonView person = new PersonView(row.get("person_id", UUID.class), row.get("display_name", String.class),
                row.get("username", String.class), row.get("avatar_url", String.class),
                Boolean.TRUE.equals(row.get("friend", Boolean.class)));
        Long joined = row.get("joined", Long.class);
        Tournament t = new Tournament(id, row.get("code", String.class), row.get("name", String.class),
                row.get("size", Integer.class), joined == null ? 0 : joined.intValue(),
                row.get("scheduled_at", Instant.class), row.get("status", String.class),
                "champion".equals(kind) ? person : null,
                Boolean.TRUE.equals(row.get("viewer_joined", Boolean.class)));
        return new FeedItem(kind, kind + ":" + id, at, person, row.get("game_type", String.class), message,
                null, null, t, null);
    }

    // ---------------------------------------------------------------- writing

    /** Post an open game request: makes the lobby room, then advertises it. */
    public Mono<CreatedPost> post(UUID author, CreatePostRequest request) {
        String type = gameTypeOf(request.gameType());
        int seats = seatsFor(type, request.seats());
        boolean ranked = Boolean.TRUE.equals(request.ranked());
        return rooms.create(author, null, type, null, null, ranked)
                // One open request per player — a new one replaces the last.
                .flatMap(room -> db.sql("""
                                UPDATE huud_posts SET status = 'closed'
                                WHERE author_id = :uid AND kind = 'game_request' AND status = 'open'
                                """).bind("uid", author).fetch().rowsUpdated()
                        .then(insert(author, "game_request", room, type, request.message(), ranked, seats, null,
                                REQUEST_TTL))
                        .map(id -> new CreatedPost(id, room)));
    }

    /** Challenge one player: makes a two-seat lobby room and asks them into it. */
    public Mono<CreatedPost> challenge(UUID author, CreateChallengeRequest request) {
        UUID target = request.targetUserId();
        if (author.equals(target)) {
            return Mono.error(ApiExceptions.badRequest("you can't challenge yourself"));
        }
        String type = gameTypeOf(request.gameType());
        boolean ranked = Boolean.TRUE.equals(request.ranked());
        return users.findById(target)
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such player")))
                .flatMap(t -> t.isBot() || t.isGuest()
                        ? Mono.error(ApiExceptions.badRequest("you can only challenge a player with an account"))
                        : rooms.create(author, null, type, null, null, ranked))
                .flatMap(room -> db.sql("""
                                UPDATE huud_posts SET status = 'closed'
                                WHERE author_id = :uid AND target_user_id = :target AND status = 'open'
                                """).bind("uid", author).bind("target", target).fetch().rowsUpdated()
                        .then(insert(author, "challenge", room, type, request.message(), ranked, 2, target,
                                CHALLENGE_TTL))
                        .map(id -> new CreatedPost(id, room)))
                .flatMap(created -> users.findById(author)
                        .doOnNext(from -> {
                            Map<String, String> data = Map.of("type", "HUUD_CHALLENGE",
                                    "postId", created.postId().toString(), "fromId", author.toString(),
                                    "fromName", from.displayName(), "gameType", type);
                            inbox.notify(target, Map.of("type", "HUUD_CHALLENGE", "data", data));
                            push.sendToUserIfOffline(target, from.displayName() + " challenged you",
                                    GAME_NAMES.getOrDefault(type, type) + " · open PlayHuud to answer", data);
                        })
                        .thenReturn(created));
    }

    private Mono<UUID> insert(UUID author, String kind, RoomView room, String type, String message, boolean ranked,
                              int seats, UUID target, Duration ttl) {
        String text = cleanMessage(message);
        var spec = db.sql("""
                        INSERT INTO huud_posts (author_id, kind, room_id, game_type, message, ranked, seats,
                                                target_user_id, expires_at)
                        VALUES (:author, :kind, :room, :game, :message, :ranked, :seats, :target, :expires)
                        RETURNING id
                        """)
                .bind("author", author).bind("kind", kind).bind("room", room.id()).bind("game", type)
                .bind("ranked", ranked).bind("seats", seats).bind("expires", Instant.now().plus(ttl));
        spec = text == null ? spec.bindNull("message", String.class) : spec.bind("message", text);
        spec = target == null ? spec.bindNull("target", UUID.class) : spec.bind("target", target);
        return spec.map((row, meta) -> row.get("id", UUID.class)).one();
    }

    /** Accept a challenge addressed to you: takes the other seat in its room. */
    public Mono<RoomView> accept(UUID viewer, UUID postId) {
        return challengeFor(viewer, postId)
                .flatMap(c -> rooms.join(c.roomCode(), viewer, null)
                        .flatMap(room -> answer(postId, "accepted").thenReturn(room))
                        .doOnNext(room -> tellAuthor(c, viewer, "accepted")));
    }

    /** "Not now": the challenge leaves your feed and its author hears so. */
    public Mono<Void> decline(UUID viewer, UUID postId) {
        return challengeFor(viewer, postId)
                .flatMap(c -> answer(postId, "declined").doOnSuccess(v -> tellAuthor(c, viewer, "declined")))
                .then();
    }

    /** Take down your own request or challenge. The lobby room itself is left alone. */
    public Mono<Void> close(UUID viewer, UUID postId) {
        return db.sql("UPDATE huud_posts SET status = 'closed' WHERE id = :id AND author_id = :uid AND status = 'open'")
                .bind("id", postId).bind("uid", viewer)
                .fetch().rowsUpdated()
                .flatMap(n -> n == 0 ? Mono.error(ApiExceptions.notFound("no open post of yours with that id"))
                        : Mono.<Void>empty());
    }

    private record OpenChallenge(UUID authorId, String roomCode, String gameType) {
    }

    private Mono<OpenChallenge> challengeFor(UUID viewer, UUID postId) {
        return db.sql("""
                        SELECT p.author_id, p.target_user_id, p.kind, p.status, p.expires_at, p.game_type, r.code
                        FROM huud_posts p JOIN rooms r ON r.id = p.room_id
                        WHERE p.id = :id
                        """)
                .bind("id", postId)
                .map((row, meta) -> new Object[]{row.get("author_id", UUID.class), row.get("target_user_id", UUID.class),
                        row.get("kind", String.class), row.get("status", String.class),
                        row.get("expires_at", Instant.class), row.get("game_type", String.class),
                        row.get("code", String.class)})
                .one()
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such challenge")))
                .flatMap(r -> {
                    if (!"challenge".equals(r[2]) || !viewer.equals(r[1])) {
                        return Mono.error(ApiExceptions.forbidden("that challenge isn't addressed to you"));
                    }
                    if (!"open".equals(r[3])) {
                        return Mono.error(ApiExceptions.conflict("that challenge was already answered"));
                    }
                    if (((Instant) r[4]).isBefore(Instant.now())) {
                        return Mono.error(ApiExceptions.conflict("that challenge has expired"));
                    }
                    return Mono.just(new OpenChallenge((UUID) r[0], (String) r[6], (String) r[5]));
                });
    }

    private Mono<Void> answer(UUID postId, String status) {
        return db.sql("UPDATE huud_posts SET status = :status, answered_at = now() WHERE id = :id AND status = 'open'")
                .bind("status", status).bind("id", postId)
                .fetch().rowsUpdated().then();
    }

    private void tellAuthor(OpenChallenge c, UUID viewer, String answer) {
        users.findById(viewer).subscribe(who -> {
            Map<String, String> data = Map.of("type", "HUUD_CHALLENGE_ANSWERED", "answer", answer,
                    "fromId", viewer.toString(), "fromName", who.displayName(), "gameType", c.gameType());
            inbox.notify(c.authorId(), Map.of("type", "HUUD_CHALLENGE_ANSWERED", "data", data));
            if ("accepted".equals(answer)) {
                push.sendToUserIfOffline(c.authorId(), who.displayName() + " accepted your challenge",
                        GAME_NAMES.getOrDefault(c.gameType(), c.gameType()) + " · your lobby is waiting", data);
            }
        }, err -> { /* best-effort, like every other inbox notice */ });
    }

    // ---------------------------------------------------------------- rules

    /** The app calls Word Bluff "bluff" in places; the server only knows "wordbluff". */
    static String gameTypeOf(String requested) {
        String type = requested == null ? "" : requested.trim().toLowerCase();
        if ("bluff".equals(type)) {
            type = "wordbluff";
        }
        if (!DEFAULT_SEATS.containsKey(type)) {
            throw ApiExceptions.badRequest("unknown gameType: " + requested);
        }
        return type;
    }

    /** "Whot", "Word Bluff" — the name people know a game by. */
    public static String gameName(String gameType) {
        return GAME_NAMES.getOrDefault(gameType, "a game");
    }

    /** A game's natural table, for anything showing "2/4 playing". Unknown games count as 2. */
    public static int seatsFor(String gameType) {
        return gameType == null || !DEFAULT_SEATS.containsKey(gameType) ? 2 : seatsFor(gameType, null);
    }

    /** Head-to-head games are always two; Ludo tops out at four; anything else 2–16. */
    static int seatsFor(String gameType, Integer requested) {
        if (HEAD_TO_HEAD.contains(gameType)) {
            return 2;
        }
        int max = "ludo".equals(gameType) ? 4 : 16;
        int seats = requested == null ? DEFAULT_SEATS.get(gameType) : requested;
        return Math.max(2, Math.min(max, seats));
    }

    static String cleanMessage(String message) {
        if (message == null) {
            return null;
        }
        String trimmed = message.strip();
        if (trimmed.isEmpty()) {
            return null;
        }
        return trimmed.length() > 280 ? trimmed.substring(0, 280) : trimmed;
    }

    /** One {@code huud_posts} row with its author/target, before the room's players are attached. */
    private record PostRow(UUID id, String kind, UUID authorId, UUID roomId, String gameType, String message,
                           boolean ranked, int seats, Instant createdAt, Instant expiresAt, String code,
                           String roomStatus, PersonView author, PersonView target) {

        static PostRow of(Row row) {
            UUID targetId = row.get("target_user_id", UUID.class);
            UUID authorId = row.get("author_id", UUID.class);
            return new PostRow(row.get("id", UUID.class), row.get("kind", String.class), authorId,
                    row.get("room_id", UUID.class), row.get("game_type", String.class),
                    row.get("message", String.class), Boolean.TRUE.equals(row.get("ranked", Boolean.class)),
                    row.get("seats", Integer.class), row.get("created_at", Instant.class),
                    row.get("expires_at", Instant.class), row.get("code", String.class),
                    row.get("room_status", String.class),
                    new PersonView(authorId, row.get("a_name", String.class), row.get("a_username", String.class),
                            row.get("a_avatar", String.class), Boolean.TRUE.equals(row.get("a_friend", Boolean.class))),
                    targetId == null ? null : new PersonView(targetId, row.get("t_name", String.class),
                            row.get("t_username", String.class), row.get("t_avatar", String.class),
                            Boolean.TRUE.equals(row.get("t_friend", Boolean.class))));
        }

        FeedItem toItem(UUID viewer, List<PersonView> players, String lastOutcome) {
            boolean joined = players.stream().anyMatch(p -> viewer.equals(p.userId()));
            boolean filled = players.size() >= seats || "in_game".equals(roomStatus);
            OpenGame game = new OpenGame(id, roomId, code, ranked, players.size(), seats, players, expiresAt,
                    joined, viewer.equals(authorId), target, lastOutcome, filled);
            return new FeedItem(kind, "post:" + id, createdAt, author, gameType, message, game, null, null, null);
        }
    }
}
