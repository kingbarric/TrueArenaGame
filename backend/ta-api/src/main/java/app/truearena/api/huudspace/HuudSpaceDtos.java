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

    public record UpdateRequest(@Size(max = 40) String name, String privacy) {
    }

    public record JoinRequest(@NotBlank @Size(min = 6, max = 6) String code) {
    }

    public record AddGameRequest(@NotBlank String gameType) {
    }

    public record Person(UUID userId, String displayName, String username, String avatarUrl,
                         boolean host, boolean here, boolean canSpeak, Instant joinedAt) {
    }

    /**
     * The game being played (or set up) in the Huud right now. Being in the
     * Huud isn't being in the game: {@code youArePlaying} says whether you have
     * a seat, {@code seats} how many there are.
     */
    public record CurrentGame(UUID roomId, String code, String gameType, String status, int players,
                              int seats, List<UUID> playerIds, boolean youArePlaying) {
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
                                Instant createdAt, Instant endedAt) {
    }

    /** A card on the Live tab. The code stays out: only people inside see it. */
    public record LiveHuud(UUID id, String name, String privacy, Person host, int memberCount,
                           List<Person> members, String gameType, String gameStatus,
                           boolean youAreIn, Instant createdAt) {
    }

    /** A card in your Huud history — everyone who was there and what you played. */
    public record HistoryHuud(UUID id, String name, String privacy, String status, boolean youCreated,
                              boolean youAreHost, Person host, List<Person> participants,
                              List<String> games, int gamesPlayed, Instant createdAt, Instant endedAt) {
    }
}
