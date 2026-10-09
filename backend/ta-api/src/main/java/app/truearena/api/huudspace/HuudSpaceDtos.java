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
     * up, and a short line to share it to the feed with.
     */
    public record CreateRequest(@Size(max = 40) String name, String privacy, String gameType,
                                @Size(max = 140) String message, Boolean share) {
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
    public static final List<String> BACKGROUNDS = List.of("blank", "lounge", "poolside", "club");

    public record JoinRequest(@NotBlank @Size(min = 6, max = 6) String code) {
    }

    /** {@code rematch}: seat the last game's players again (whoever's still in the Huud). */
    public record AddGameRequest(@NotBlank String gameType, Boolean rematch) {
    }

    /**
     * Someone in a Huud. {@code here}: in the Live hangout right now. {@code host}:
     * running it right now; {@code owner}: whose Huud it is, for good.
     */
    public record Person(UUID userId, String displayName, String username, String avatarUrl,
                         boolean host, boolean here, boolean canSpeak, Instant joinedAt, boolean owner) {

        public Person(UUID userId, String displayName, String username, String avatarUrl,
                      boolean host, boolean here, boolean canSpeak, Instant joinedAt) {
            this(userId, displayName, username, avatarUrl, host, here, canSpeak, joinedAt, false);
        }
    }

    /** Going Live: who to tell — "all" members, "online" members only, or "none". */
    public record GoLiveRequest(@com.fasterxml.jackson.annotation.JsonProperty("notify") String tell) {
    }

    public record MuteRequest(Boolean muted) {
    }

    /**
     * A Huud you belong to, for the Huud tab: yours first, live ones on top.
     * {@code liveCount}: people in the Live hangout now; {@code memberCount}: everyone.
     */
    public record MyHuud(UUID id, String name, String privacy, boolean live, boolean youOwn, boolean youAreHost,
                         Person host, int memberCount, int liveCount, List<Person> members, String gameType,
                         String gameStatus, String background, boolean muted, Instant liveSince) {
    }

    /**
     * The game being played (or set up) in the Huud right now. Being in the
     * Huud isn't being in the game: {@code youArePlaying} says whether you have
     * a seat, {@code seats} how many there are. {@code code} only goes to the
     * players and the host — anyone else watches by {@code roomId}, so the
     * host's roster can't be skipped.
     */
    public record CurrentGame(UUID roomId, String code, String gameType, String status, int players,
                              int seats, List<UUID> playerIds, boolean youArePlaying, List<UUID> readyIds,
                              List<Seat> table) {
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
     * the host has to answer, and is empty for everyone else.
     */
    public record HuudSpaceView(UUID id, String code, String name, String privacy, String status,
                                Person host, List<Person> members, CurrentGame currentGame,
                                boolean youAreIn, boolean youAreHost, boolean youCanSpeak, String voiceRoom,
                                String joinRequest, String playRequest, String micRequest,
                                List<PendingRequest> requests, boolean shared, String feedMessage,
                                int watching, String background, Instant createdAt, Instant endedAt,
                                boolean live, boolean youOwn, boolean muted, int memberCount, int liveCount) {
    }

    /** A card on the Live tab. The code stays out: only people inside see it. */
    public record LiveHuud(UUID id, String name, String privacy, Person host, int memberCount,
                           List<Person> members, String gameType, String gameStatus,
                           boolean youAreIn, int watching, Instant createdAt) {
    }

}
