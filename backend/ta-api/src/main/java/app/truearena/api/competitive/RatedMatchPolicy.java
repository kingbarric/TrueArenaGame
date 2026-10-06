package app.truearena.api.competitive;

import java.util.List;
import java.util.Optional;

/**
 * Decides whether a finished game moves anyone's rating. Pure — every input is
 * passed in — so the rules are testable without a database and readable in one
 * place.
 *
 * <p>The host's "ranked" flag is a request; this is the decision. An unrated
 * match is still recorded, with the reason returned here, because that raw
 * history is what makes farming and alt accounts investigable later.
 */
public final class RatedMatchPolicy {

    /** Why a match wasn't rated. Persisted verbatim in {@code match_records.unranked_reason}. */
    public enum UnrankedReason {
        UNRATED_GAME_TYPE("unrated_game_type"),
        CASUAL_ROOM("casual_room"),
        VS_AGENT("vs_agent"),
        GUEST_PLAYER("guest_player"),
        TOO_FEW_HUMANS("too_few_humans"),
        REPEAT_OPPONENT("repeat_opponent");

        private final String code;

        UnrankedReason(String code) {
            this.code = code;
        }

        public String code() {
            return code;
        }
    }

    /** One seat in the finished game, as far as eligibility cares. */
    public record Seat(String userId, boolean bot, boolean guest) {
    }

    private final CompetitiveSettings settings;

    public RatedMatchPolicy(CompetitiveSettings settings) {
        this.settings = settings;
    }

    /**
     * @param roomRequestedRanked the host asked for a rated match
     * @param championship        the game is part of a tournament bracket (always rated when otherwise eligible)
     * @param maxPairGamesToday   the most rated games any pair of these players has
     *                            already played against each other in the last 24h
     * @return empty when the match is rated, otherwise why not
     */
    public Optional<UnrankedReason> decide(String gameType, boolean roomRequestedRanked, boolean championship,
                                           List<Seat> seats, int maxPairGamesToday) {
        if (!settings.isRated(gameType)) {
            return Optional.of(UnrankedReason.UNRATED_GAME_TYPE);
        }
        if (!roomRequestedRanked && !championship) {
            return Optional.of(UnrankedReason.CASUAL_ROOM);
        }
        if (seats.stream().anyMatch(Seat::bot)) {
            // Cyber Agents are a free shared pool: rating them would make the
            // nearest agent a zero-risk rating farm (same reasoning as coins).
            return Optional.of(UnrankedReason.VS_AGENT);
        }
        if (seats.stream().anyMatch(Seat::guest)) {
            // Guests are a device, not a verified person — trivially multipliable.
            return Optional.of(UnrankedReason.GUEST_PLAYER);
        }
        if (seats.stream().map(Seat::userId).distinct().count() < 2) {
            return Optional.of(UnrankedReason.TOO_FEW_HUMANS);
        }
        if (maxPairGamesToday >= settings.maxRatedGamesPerPairPerDay()) {
            return Optional.of(UnrankedReason.REPEAT_OPPONENT);
        }
        return Optional.empty();
    }
}
