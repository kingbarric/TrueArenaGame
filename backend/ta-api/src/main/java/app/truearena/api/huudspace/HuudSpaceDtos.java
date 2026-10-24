package app.truearena.api.huudspace;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class HuudSpaceDtos {
    private HuudSpaceDtos() {
    }

    /** Friends is the default: a Huud is for people you know unless you say otherwise. */
    public static final List<String> PRIVACY = List.of("friends", "private", "public");

    /**
     * Name and privacy make the Huud. The rest is optional: a first game to set
     * up (with its {@code mode} — Whot's "classic" or "tell"), and a short
     * line to share it to the feed with. {@code another}: make a new Huud even
     * if you have one (up to five) — without it, as older apps send, this opens
     * the one you have. {@code switchLive}: if another of yours is Live, end
     * its Live — a new Huud goes Live straight away, and only one can be.
     */
    public record CreateRequest(@Size(max = 40) String name, String privacy, String gameType,
                                @Size(max = 140) String message, Boolean share, String mode, java.util.Map<String, Object> gameConfig,
                                Boolean another, Boolean switchLive) {
        public CreateRequest(String name, String privacy, String gameType, String message, Boolean share, String mode,
                             java.util.Map<String, Object> gameConfig) {
            this(name, privacy, gameType, message, share, mode, gameConfig, null, null);
        }
    }

    public record ShareRequest(@Size(max = 140) String message) {
    }

    public record AnswerRequest(Boolean accept) {
    }

    public record MicRequest(Boolean allowed) {
    }

    public record InviteRequest(@jakarta.validation.constraints.NotNull UUID userId) {
    }

    public record SendMessage(@NotBlank @Size(max = 300) String body) {
    }

    public record ChatMessage(long id, Person from, String body, Instant at) {
    }

    /** Someone asking the host for something: to come in, to play, or for the mic. */
    public record PendingRequest(Person from, String kind, Instant at) {
    }

    /** {@code background}: "lounge", "poolside", "club", or "default" for none. Null fields stay as they are. */
    public record UpdateRequest(@Size(max = 40) String name, String privacy, String background) {
    }

    /** Pickable backdrops; none chosen ("default", stored as null) is the disco floor, "blank" is no picture. */
    public static final List<String> BACKGROUNDS = List.of("blank", "disco", "lounge", "poolside", "club");

    /** What an invite link's web page may show — nothing beyond the name and how busy it is. */
    public record InvitePreview(String code, String name, String owner, boolean live, int members) {
    }

    public record JoinRequest(@NotBlank @Size(min = 6, max = 6) String code) {
    }

    /**
     * {@code rematch}: seat the last game's players again (whoever's still in the Huud),
     * in the same mode. {@code mode}: Whot's "classic" (the default) or "tell".
     */
    public record AddGameRequest(@NotBlank String gameType, Boolean rematch, String mode, java.util.Map<String, Object> gameConfig) {
    }

    /**
     * Someone in a Huud. {@code here}: in the Live hangout right now. {@code host}:
     * running it right now; {@code owner}: whose Huud it is, for good.
     */
    public record Person(UUID userId, String displayName, String username, String avatarUrl,
                         boolean host, boolean here, boolean canSpeak, Instant joinedAt, boolean owner, String huudAvatarId, String huudOutfitId) {

        public Person(UUID userId, String displayName, String username, String avatarUrl,
                      boolean host, boolean here, boolean canSpeak, Instant joinedAt, boolean owner) {
            this(userId,displayName,username,avatarUrl,host,here,canSpeak,joinedAt,owner,null,null);
        }

        public Person(UUID userId, String displayName, String username, String avatarUrl,
                      boolean host, boolean here, boolean canSpeak, Instant joinedAt) {
            this(userId, displayName, username, avatarUrl, host, here, canSpeak, joinedAt, false);
        }
    }

    /**
     * Going Live: who to tell — "all" members, "online" members only, or "none".
     * {@code switchLive}: end your other Huud's Live first — only one of yours
     * can be Live, and without it that's refused.
     */
    public record GoLiveRequest(@com.fasterxml.jackson.annotation.JsonProperty("notify") String tell, Boolean switchLive) {
        public GoLiveRequest(String tell) {
            this(tell, null);
        }
    }

    /**
     * The Live hangout you're in somewhere else — you're in one at a time. Seen
     * on a Huud you belong to that's Live but that you haven't walked into, so
     * the app can offer to bring you over. {@code playing}: you're in a game
     * there, so you finish that first.
     */
    public record Elsewhere(UUID id, String name, boolean playing) {
    }

    public record MuteRequest(Boolean muted) {
    }

    /**
     * A Huud you belong to, for the Huud tab: yours first, live ones on top.
     * {@code liveCount}: people in the Live hangout now; {@code memberCount}: everyone.
     * {@code quiet}: still Live, but nobody in it has had the app open for 15
     * minutes — it shows amber here and is kept off the Live tab.
     */
    public record MyHuud(UUID id, String name, String privacy, boolean live, boolean youOwn, boolean youAreHost,
                         Person host, int memberCount, int liveCount, List<Person> members, String gameType,
                         String gameStatus, String background, boolean muted, Instant liveSince,
                         ChampionshipLine championship, boolean quiet) {
    }

    /**
     * What a Huud card says while a championship is on: its name and game,
     * registering → playing (with the round, e.g. "Quarter Finals") → finished.
     */
    public record ChampionshipLine(String name, String gameType, String status, String roundName) {
    }

    /**
     * The game being played (or set up) in the Huud right now. Being in the
     * Huud isn't being in the game: {@code youArePlaying} says whether you have
     * a seat, {@code seats} how many there are. {@code code} only goes to the
     * players and the host — anyone else watches by {@code roomId}, so the
     * host's roster can't be skipped. {@code mode}: Whot's "classic" or "tell";
     * null for every other game.
     */
    public record CurrentGame(UUID roomId, String code, String gameType, String status, int players,
                              int seats, List<UUID> playerIds, boolean youArePlaying, List<UUID> readyIds,
                              List<Seat> table, String mode) {
    }

    /** Someone at the table — a person from the Huud or a Cyber Agent — and whether they're ready. */
    public record Seat(UUID userId, String displayName, String avatarUrl, boolean bot, boolean ready) {
    }

    public record PickRequest(@jakarta.validation.constraints.NotNull List<UUID> userIds) {
    }

    /**
     * A Huud as someone inside it — or allowed to look in — sees it.
     * {@code joinRequest} / {@code playRequest} / {@code micRequest} are your own
     * asks ("pending", "accepted", "declined" or null); {@code requests} is what
     * the host has to answer; eligible mic cover sees mic requests only.
     * {@code quiet}: Live, but nobody in the hangout has had the app open lately.
     * {@code elsewhere}: you belong here, it's Live, and you're in another
     * Huud's hangout instead — opening this one doesn't pull you out of that.
     */
    public record HuudSpaceView(UUID id, String code, String name, String privacy, String status,
                                Person host, List<Person> members, CurrentGame currentGame,
                                boolean youAreIn, boolean youAreHost, boolean youCanSpeak, String voiceRoom,
                                String joinRequest, String playRequest, String micRequest,
                                List<PendingRequest> requests, boolean shared, String feedMessage,
                                int watching, String background, Instant createdAt, Instant endedAt,
                                boolean live, boolean youOwn, boolean muted, int memberCount, int liveCount,
                                UUID championshipId, boolean youCanManageMic, boolean findingPlayers, boolean quiet,
                                Elsewhere elsewhere) {
    }

    /**
     * A card on the Live tab. The code stays out: only people inside see it.
     * {@code moments}: what's going on in there, newest first;
     * {@code gamesPlayed} since it went Live; {@code recentMessages} in the
     * last half hour (a count — the chat itself stays with its members).
     */
    public record LiveHuud(UUID id, String name, String privacy, Person host, int memberCount,
                           List<Person> members, String gameType, String gameStatus,
                           boolean youAreIn, int watching, Instant createdAt, ChampionshipLine championship, boolean findingPlayers,
                           String background, List<Moment> moments, int gamesPlayed, int recentMessages) {
    }

    /**
     * Something that just happened in a Live Huud. {@code kind}: play (a move
     * in the game on now), win, joined, live (went Live), chat — chat only
     * reaches the Huud's own members. {@code who} is empty for the game
     * itself ("Nobody was murdered last night"); {@code at} is empty for a
     * play, which is happening now.
     */
    public record Moment(String kind, Person who, String text, Instant at) {
    }

    // ------------------------------------------------------------ championships

    /**
     * Start a championship in the Huud. Everything has a default: Chess or
     * Draughts (required), up to 8 players, simultaneous rounds, watching
     * allowed, 3 minutes to come back after a disconnect, named after the
     * game, starting in 15 minutes.
     */
    public record ChampionshipRequest(@NotBlank String gameType, Integer size, String roundTiming,
                                      Boolean spectatorsAllowed, Integer graceMinutes, @Size(max = 80) String name,
                                      Instant startsAt) {
        public ChampionshipRequest(String gameType, Integer size, String roundTiming, Boolean spectatorsAllowed,
                                   Integer graceMinutes, String name) {
            this(gameType, size, roundTiming, spectatorsAllowed, graceMinutes, name, null);
        }
    }

    /** Someone in the bracket. {@code out}: knocked out. */
    public record Entrant(UUID userId, String name, String username, String avatarUrl, boolean out) {
    }

    /**
     * One pairing. {@code status}: pending (waiting for its players), active
     * (being played — {@code roomId} and {@code voiceRoom} set), completed,
     * bye or no_winner. {@code gameNumber} counts replays after draws.
     */
    public record ChampionshipMatch(UUID id, int round, String roundName, int position, UUID playerA, UUID playerB,
                                    UUID winnerId, String status, UUID roomId, int gameNumber, int watching,
                                    String voiceRoom, long aReconnectMs, long bReconnectMs) {
    }

    /**
     * A Huud's championship as everyone in the Huud sees it. {@code status}:
     * registering → playing → finished (or cancelled). {@code lobbyVoiceRoom}
     * is the Huud's own voice room, the championship lobby. {@code startsAt}:
     * when it starts by itself; the host can start it sooner once
     * {@code minPlayers} have registered. {@code size} is the most players
     * while registering, then the bracket they were drawn into.
     */
    public record HuudChampionship(UUID id, UUID huudSpaceId, String name, String gameType, int size,
                                   String status, String roundTiming, boolean spectatorsAllowed, int graceSeconds,
                                   int currentRound, int rounds, String roundName, List<Entrant> players,
                                   boolean youAreRegistered, List<ChampionshipMatch> matches, UUID championId,
                                   UUID runnerUpId, UUID yourMatchId, String lobbyVoiceRoom, UUID createdBy,
                                   Instant startsAt, int minPlayers) {
    }
}
