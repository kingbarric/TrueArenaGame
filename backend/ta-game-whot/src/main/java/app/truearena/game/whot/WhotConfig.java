package app.truearena.game.whot;

import app.truearena.engine.GameSettings;

/**
 * Whot's house rules. Every special is a switch, and every one of them starts
 * on — they're how the game is normally played, but tables differ and an
 * argument about whether twos stack is better settled before the deal than
 * during it.
 *
 * @param turnSeconds     how long a player has to play or draw
 * @param startingHand    cards dealt to each player
 * @param includeWhot     whether the five wild Whot cards are in the deck at
 *                        all — plenty of tables leave them out
 * @param pickTwo         2 makes the next player draw two
 * @param pickTwoStacking a player facing a 2 may answer with their own,
 *                        passing the penalty on and adding to it
 * @param generalMarket   14 makes everyone but the player who dealt it draw one
 * @param holdOn          1 lets the player take another turn
 * @param suspension      8 skips the next player
 */
public record WhotConfig(
        int turnSeconds,
        int startingHand,
        boolean includeWhot,
        boolean pickTwo,
        boolean pickTwoStacking,
        boolean generalMarket,
        boolean holdOn,
        boolean suspension,
        String mode,
        String tellRule,
        int tellMinCards
) implements GameSettings {

    public WhotConfig(int turnSeconds, int startingHand, boolean includeWhot,
                      boolean pickTwo, boolean pickTwoStacking, boolean generalMarket,
                      boolean holdOn, boolean suspension) {
        this(turnSeconds, startingHand, includeWhot, pickTwo, pickTwoStacking,
                generalMarket, holdOn, suspension, "classic", "either", 3);
    }

    public WhotConfig(int turnSeconds, int startingHand, boolean includeWhot,
                      boolean pickTwo, boolean pickTwoStacking, boolean generalMarket,
                      boolean holdOn, boolean suspension, String mode) {
        this(turnSeconds, startingHand, includeWhot, pickTwo, pickTwoStacking,
                generalMarket, holdOn, suspension, mode, "either", 3);
    }

    public WhotConfig {
        if (turnSeconds < 10 || turnSeconds > 300) {
            throw new IllegalArgumentException("turnSeconds out of range: " + turnSeconds);
        }
        if (startingHand < 3 || startingHand > 12) {
            throw new IllegalArgumentException("startingHand out of range: " + startingHand);
        }
        if (!"classic".equals(mode) && !"tell".equals(mode)) {
            throw new IllegalArgumentException("unknown Whot mode: " + mode);
        }
        if (!"either".equals(tellRule) && !"value".equals(tellRule) && !"shape".equals(tellRule)) {
            throw new IllegalArgumentException("unknown Tell rule: " + tellRule);
        }
        if (tellMinCards < 2 || tellMinCards > 12) {
            throw new IllegalArgumentException("Tell minimum must be 2 to 12 cards");
        }
    }

    public boolean tell() { return "tell".equals(mode); }

    public static WhotConfig defaults() {
        return new WhotConfig(60, 5, false, true, true, true, true, true);
    }
}
