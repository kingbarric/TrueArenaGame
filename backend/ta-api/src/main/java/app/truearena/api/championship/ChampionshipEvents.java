package app.truearena.api.championship;

import java.util.UUID;

/**
 * What a championship tells the place it runs in — for a Huud, everyone in it
 * refreshes, and players hear their match is ready. Best effort: a listener
 * failing never stops the bracket.
 */
public interface ChampionshipEvents {
    /** The bracket, a match or the result changed. */
    void changed(UUID championshipId);

    /** A match has a board waiting for its two players. */
    void matchReady(UUID championshipId, UUID matchId, UUID playerA, UUID playerB);
}
