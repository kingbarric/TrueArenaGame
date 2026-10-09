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

    public record CreateRequest(@Size(max = 40) String name, String privacy) {
    }

    public record UpdateRequest(@Size(max = 40) String name, String privacy) {
    }

    public record JoinRequest(@NotBlank @Size(min = 6, max = 6) String code) {
    }

    public record AddGameRequest(@NotBlank String gameType) {
    }

    public record Person(UUID userId, String displayName, String username, String avatarUrl,
                         boolean host, boolean here, Instant joinedAt) {
    }

    /** The game being played (or set up) in the Huud right now. */
    public record CurrentGame(UUID roomId, String code, String gameType, String status, int players) {
    }

    /** A Huud as someone inside it — or allowed to look in — sees it. */
    public record HuudSpaceView(UUID id, String code, String name, String privacy, String status,
                                Person host, List<Person> members, CurrentGame currentGame,
                                boolean youAreIn, boolean youAreHost, String voiceRoom,
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
