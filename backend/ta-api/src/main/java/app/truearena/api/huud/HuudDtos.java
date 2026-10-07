package app.truearena.api.huud;

import app.truearena.api.room.RoomDtos.RoomView;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class HuudDtos {

    private HuudDtos() {
    }

    /** "Your Huud" is you and your friends; "For you" is the whole public lobby. */
    public enum Tab { FRIENDS, FOR_YOU }

    /** The chip row under the search bar. */
    public enum Filter { ALL, OPEN, WINS, TOURNAMENTS }

    /** A person on a card. {@code friend} lets the client offer Challenge vs. Add friend without a lookup. */
    public record PersonView(UUID userId, String displayName, String username, String avatarUrl, boolean friend) {
    }

    /**
     * One feed card. {@code kind} picks which of the three detail blocks is set:
     * {@code game_request} / {@code challenge} → {@code game}; {@code win} → {@code win};
     * {@code tournament} / {@code champion} → {@code tournament}.
     */
    public record FeedItem(String kind, String id, Instant at, PersonView actor, String gameType, String message,
                           OpenGame game, Win win, Tournament tournament) {
    }

    /**
     * An open game request or a challenge. {@code target} is set for a challenge;
     * {@code lastOutcome} is the viewer's result the last time these two played
     * this game ("won" / "lost" / "tied"), which is what makes it a rematch.
     */
    public record OpenGame(UUID postId, UUID roomId, String roomCode, boolean ranked, int seatsTaken, int seats,
                           List<PersonView> players, Instant expiresAt, boolean joined, boolean mine,
                           PersonView target, String lastOutcome) {
    }

    /**
     * A verified win from match history. {@code recent} is that player's last
     * results in this game, newest first ("won" / "lost" / "tied"); {@code streak}
     * counts the wins at the front of it.
     */
    public record Win(UUID matchId, boolean ranked, int streak, List<String> recent, Double rating,
                      Double weekDelta, List<String> beaten) {
    }

    /** A championship open for registration, or one that just crowned a champion. */
    public record Tournament(UUID championshipId, String code, String name, int size, int joined,
                             Instant scheduledAt, String status, PersonView champion, boolean viewerJoined) {
    }

    public record CreatePostRequest(@NotBlank String gameType, @Size(max = 280) String message, Boolean ranked,
                                    Integer seats) {
    }

    public record CreateChallengeRequest(@NotNull UUID targetUserId, @NotBlank String gameType,
                                         @Size(max = 280) String message, Boolean ranked) {
    }

    /** What posting returns: the new post's id and the lobby the author should walk into. */
    public record CreatedPost(UUID postId, RoomView room) {
    }
}
