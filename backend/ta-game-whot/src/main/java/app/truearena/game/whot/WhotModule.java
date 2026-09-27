package app.truearena.game.whot;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameModule;
import app.truearena.engine.GameSettings;
import app.truearena.engine.GameState;
import app.truearena.engine.Phase;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.PlayerVisibleState;
import app.truearena.engine.PublicBroadcastState;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import app.truearena.engine.WinResult;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Whot — the shedding game. Match the card in play by shape or by number,
 * draw from the market when you can't, and the first player to empty their
 * hand wins.
 *
 * <p>The specials (pick two, general market, hold on, suspension, and the
 * wild Whot card) are each a switch on {@link WhotConfig}, because tables
 * genuinely disagree about them — whether twos stack most of all.
 *
 * <p>Two to twenty can play. Past a certain table size one deck can't seat
 * everybody, so more are shuffled in: see {@link #buildDeck}.
 */
public final class WhotModule implements GameModule {

    /** Numbers printed on each shape. No 6 and no 9 — upside down they're the same card. */
    private static final int[] TWELVE = {1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14};
    private static final int[] NINE = {1, 2, 3, 5, 7, 10, 11, 13, 14};
    private static final int[] SEVEN = {1, 2, 3, 4, 5, 7, 8};
    private static final int WHOT_COPIES = 5;

    /** Spare cards a deal wants on top of everyone's hand, so the market isn't bare. */
    private static final int MARKET_HEADROOM = 24;

    /** Maximum startup pause before the table deals itself in and opens play. */
    private static final int DEAL_SECONDS = 5;

    /** Nobody can be dealt fewer than this, however eager the dealer is to start. */
    private static final int MIN_HAND = 3;

    public static final int MIN_PLAYERS = 2;
    public static final int MAX_PLAYERS = 20;

    @Override
    public String gameType() {
        return "whot";
    }

    @Override
    public List<Phase> definePhases(GameSettings settings) {
        WhotConfig config = (WhotConfig) settings;
        // Rooms created before the 60-second default may still carry a shorter
        // setting. Give those turns the same minimum grace before pausing.
        int turnSeconds = Math.max(60, config.turnSeconds());
        return List.of(
                // The dealer may start sooner, but the table automatically
                // deals and opens play after five seconds so game startup is
                // always quick (see onPhaseElapsed).
                new Phase("Deal", DEAL_SECONDS),
                new Phase("Turn", turnSeconds),
                Phase.awaitingResume("Waiting", turnSeconds),
                Phase.untimed("Results"));
    }

    // ---------------------------------------------------------------- setup

    @Override
    public GameState initialState(List<String> playerIds, GameSettings settings, RandomSource rng) {
        WhotConfig config = (WhotConfig) settings;
        if (playerIds.size() < MIN_PLAYERS || playerIds.size() > MAX_PLAYERS) {
            throw new RuleViolation("BAD_PLAYER_COUNT",
                    "Whot seats " + MIN_PLAYERS + " to " + MAX_PLAYERS + " players");
        }

        WhotState.Draft d = new WhotState.Draft();
        d.config = config;
        d.players = new ArrayList<>(playerIds);
        d.market = buildDeck(config, playerIds.size());
        shuffle(d.market, rng);
        for (String p : playerIds) {
            d.hands.put(p, new ArrayList<>());
        }
        // Nothing is dealt yet: the dealer does that, by hand, in the Deal
        // phase.
        d.phase = "Deal";

        d.emit("GAME_STARTED", Map.of(
                "players", List.copyOf(playerIds),
                "dealer", playerIds.get(0),
                "suggestedHand", config.startingHand(),
                "turnSeconds", config.turnSeconds(),
                "marketLeft", d.market.size(),
                "handSizes", handSizes(d),
                "rules", rulesSummary(config)));
        return d.build();
    }

    /**
     * One deck is 54 cards (49 without the Whots), which doesn't stretch far
     * across a big table — twenty players at five cards each is most of two
     * decks before anyone draws. So enough are shuffled together to deal
     * everybody in and leave a market worth drawing from.
     */
    static List<WhotCard> buildDeck(WhotConfig config, int playerCount) {
        List<WhotCard> one = singleDeck(config);
        int needed = playerCount * config.startingHand() + MARKET_HEADROOM;
        int copies = Math.max(1, (int) Math.ceil(needed / (double) one.size()));

        List<WhotCard> deck = new ArrayList<>(one.size() * copies);
        for (int i = 0; i < copies; i++) {
            deck.addAll(one);
        }
        return deck;
    }

    static List<WhotCard> singleDeck(WhotConfig config) {
        List<WhotCard> deck = new ArrayList<>(54);
        for (int n : TWELVE) {
            deck.add(new WhotCard(WhotCard.Shape.CIRCLE, n));
            deck.add(new WhotCard(WhotCard.Shape.TRIANGLE, n));
        }
        for (int n : NINE) {
            deck.add(new WhotCard(WhotCard.Shape.CROSS, n));
            deck.add(new WhotCard(WhotCard.Shape.SQUARE, n));
        }
        for (int n : SEVEN) {
            deck.add(new WhotCard(WhotCard.Shape.STAR, n));
        }
        if (config.includeWhot()) {
            for (int i = 0; i < WHOT_COPIES; i++) {
                deck.add(new WhotCard(WhotCard.Shape.WHOT, WhotCard.WHOT_NUMBER));
            }
        }
        return deck;
    }

    private static void shuffle(List<WhotCard> cards, RandomSource rng) {
        for (int i = cards.size() - 1; i > 0; i--) {
            int j = rng.nextInt(i + 1);
            WhotCard tmp = cards.get(i);
            cards.set(i, cards.get(j));
            cards.set(j, tmp);
        }
    }

    // ---------------------------------------------------------------- actions

    /** Your hand is yours alone, and it changes on other people's turns too. */
    @Override
    public boolean hasPrivatePlayerState() {
        return true;
    }

    @Override
    public GameState onPlayerAction(GameState state, PlayerAction action) {
        WhotState s = (WhotState) state;
        if (s.finished() || s.appliedActionIds.contains(action.actionId())) {
            return s;
        }
        WhotState.Draft d = new WhotState.Draft(s);
        d.appliedActionIds.add(action.actionId());

        switch (action.type()) {
            case "SHUFFLE" -> shuffleAction(d, s, action);
            case "DEAL" -> dealAction(d, s, action);
            case "START" -> startAction(d, s, action);
            case "PLAY" -> play(d, s, action);
            case "DRAW" -> drawAction(d, s, action);
            case "FORFEIT" -> forfeit(d, s, action);
            default -> throw new RuleViolation("UNKNOWN_ACTION", "no handler for " + action.type());
        }
        return d.build();
    }

    /** Whoever sits first deals — they shuffle, deal, and call the start. */
    private static String dealerOf(WhotState s) {
        return s.players.get(0);
    }

    private static void requireDealing(WhotState s, String actor) {
        require("Deal".equals(s.phase), "WRONG_PHASE", "the cards are already out");
        require(actor.equals(dealerOf(s)), "NOT_THE_DEALER", "only the dealer handles the cards");
    }

    /**
     * Shuffles what's left in the market. Any cards already dealt go back in
     * first — a reshuffle mid-deal should be a genuine fresh start, not a
     * shuffle of the leftovers.
     */
    private void shuffleAction(WhotState.Draft d, WhotState s, PlayerAction a) {
        requireDealing(s, a.actor());
        for (List<WhotCard> hand : d.hands.values()) {
            d.market.addAll(hand);
            hand.clear();
        }
        // The action id is the only entropy the module is handed here, and
        // it's fresh per tap — enough to cut the deck differently each time.
        long seed = a.actionId() == null ? d.seq : a.actionId().hashCode();
        shuffle(d.market, RandomSource.seeded(seed));
        d.emit("DECK_SHUFFLED", Map.of(
                "by", a.actor(), "marketLeft", d.market.size(), "handSizes", handSizes(d)));
    }

    /** One tap deals one card to every player, the way a hand is dealt round a table. */
    private void dealAction(WhotState.Draft d, WhotState s, PlayerAction a) {
        requireDealing(s, a.actor());
        int rounds = a.data().get("rounds") instanceof Number n ? n.intValue() : 1;
        require(rounds >= 1 && rounds <= 12, "BAD_DEAL", "deal between 1 and 12 rounds at a time");

        for (int r = 0; r < rounds; r++) {
            require(d.market.size() >= d.players.size() + MARKET_HEADROOM / 2,
                    "NOT_ENOUGH_CARDS", "not enough cards left to deal another round");
            for (String p : d.players) {
                d.hands.get(p).add(d.market.remove(d.market.size() - 1));
            }
        }
        d.emit("CARDS_DEALT", Map.of(
                "by", a.actor(), "rounds", rounds,
                "marketLeft", d.market.size(), "handSizes", handSizes(d)));
        for (String p : d.players) {
            d.emitToPlayer("YOUR_HAND",
                    Map.of("cards", d.hands.get(p).stream().map(WhotCard::code).toList()), p);
        }
    }

    /** Ends the deal and turns the first card over. */
    private void startAction(WhotState.Draft d, WhotState s, PlayerAction a) {
        requireDealing(s, a.actor());
        for (String p : d.players) {
            require(d.hands.get(p).size() >= MIN_HAND, "DEAL_FIRST",
                    "everyone needs at least " + MIN_HAND + " cards");
        }
        beginPlay(d);
    }

    /** Turns the first card over and hands the game to the first player. */
    private void beginPlay(WhotState.Draft d) {
        WhotCard first = draw(d);
        while (isSpecial(first, d.config) && !d.market.isEmpty()) {
            d.pile.add(first);
            first = draw(d);
        }
        d.pile.add(first);
        d.phase = "Turn";
        d.emit("PLAY_BEGAN", Map.of("topCard", first.code(), "handSizes", handSizes(d)));
        announceTurn(d);
    }

    private void play(WhotState.Draft d, WhotState s, PlayerAction a) {
        require(isPlayableTurn(s.phase), "WRONG_PHASE", "the cards aren't dealt yet");
        requireTurn(s, a.actor());
        WhotCard card = WhotCard.parse(String.valueOf(a.data().get("card")));
        List<WhotCard> hand = d.hands.get(a.actor());
        int at = hand.indexOf(card);
        require(at >= 0, "NOT_IN_HAND", "you don't hold that card");

        // Facing a penalty, the only way out is another two — and only if
        // this table lets them stack.
        if (d.pendingPick > 0) {
            boolean answering = card.number() == 2 && d.config.pickTwo() && d.config.pickTwoStacking();
            require(answering, "MUST_PICK",
                    "you owe " + d.pendingPick + " cards — draw them, or answer with a 2");
        } else {
            require(matches(card, s), "DOESNT_MATCH", "that doesn't match the card in play");
        }

        hand.remove(at);
        d.pile.add(card);
        d.demandedShape = null;
        // A resumed waiting turn becomes a normal turn as soon as the player
        // acts. This also resets the timeout pause for whoever plays next.
        d.phase = "Turn";

        WhotCard.Shape called = null;
        if (card.isWhot()) {
            Object raw = a.data().get("shape");
            require(raw != null, "SHAPE_REQUIRED", "name the shape you want");
            called = WhotCard.Shape.valueOf(String.valueOf(raw).toUpperCase());
            require(called != WhotCard.Shape.WHOT, "BAD_SHAPE", "call a real shape");
            d.demandedShape = called;
        }

        d.emit("CARD_PLAYED", Map.of(
                "by", a.actor(),
                "card", card.code(),
                "calledShape", called == null ? "" : called.name().toLowerCase(),
                "handSizes", handSizes(d)));

        if (hand.isEmpty()) {
            finish(d, a.actor());
            return;
        }
        applySpecial(d, card, a.actor());
    }

    /** Pick two, general market, hold on and suspension — each only if this table plays it. */
    private void applySpecial(WhotState.Draft d, WhotCard card, String by) {
        WhotConfig c = d.config;
        if (card.number() == 2 && c.pickTwo()) {
            d.pendingPick += 2;
            advance(d, 1);
            return;
        }
        if (card.number() == 14 && c.generalMarket()) {
            for (String p : d.players) {
                if (!p.equals(by)) {
                    d.hands.get(p).add(draw(d));
                }
            }
            d.emit("GENERAL_MARKET", Map.of("by", by, "handSizes", handSizes(d)));
            advance(d, 1);
            return;
        }
        if (card.number() == 1 && c.holdOn()) {
            // A new turn, even though the same player keeps it.
            d.round++;
            announceTurn(d);
            return;
        }
        if (card.number() == 8 && c.suspension()) {
            advance(d, 2); // straight past the next player
            return;
        }
        advance(d, 1);
    }

    private void drawAction(WhotState.Draft d, WhotState s, PlayerAction a) {
        require(isPlayableTurn(s.phase), "WRONG_PHASE", "the cards aren't dealt yet");
        requireTurn(s, a.actor());
        int count = Math.max(1, d.pendingPick);
        List<WhotCard> hand = d.hands.get(a.actor());
        List<String> taken = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            WhotCard card = draw(d);
            hand.add(card);
            taken.add(card.code());
        }
        boolean wasPenalty = d.pendingPick > 0;
        d.pendingPick = 0;

        d.emit("CARD_DRAWN", Map.of(
                "by", a.actor(),
                "count", count,
                "penalty", wasPenalty,
                "handSizes", handSizes(d)));
        // Only the drawer learns what they actually took.
        d.emitToPlayer("YOUR_DRAW", Map.of("cards", taken), a.actor());
        advance(d, 1);
    }

    /** A player may end the table early; the next occupied seat takes the win. */
    private void forfeit(WhotState.Draft d, WhotState s, PlayerAction a) {
        int actor = s.players.indexOf(a.actor());
        require(actor >= 0, "NOT_A_PLAYER", "you're not in this game");
        String winner = s.players.get((actor + 1) % s.players.size());
        d.emit("PLAYER_FORFEITED", Map.of("player", a.actor(), "winner", winner));
        finish(d, winner);
    }

    // ---------------------------------------------------------------- turn flow

    @Override
    public GameState onPhaseElapsed(GameState state, String endedPhase) {
        WhotState s = (WhotState) state;
        if (s.finished()) {
            return s;
        }
        WhotState.Draft d = new WhotState.Draft(s);
        if ("Deal".equals(s.phase)) {
            // The dealer never called it, so the table deals itself in and
            // gets on with the game.
            while (d.hands.get(d.players.get(0)).size() < d.config.startingHand()
                    && d.market.size() >= d.players.size() + MARKET_HEADROOM / 2) {
                for (String p : d.players) {
                    d.hands.get(p).add(d.market.remove(d.market.size() - 1));
                }
            }
            beginPlay(d);
            return d.build();
        }
        // Keep the same player and the same hand. Entering an awaiting-resume
        // phase makes the orchestrator pause the room until somebody resumes,
        // matching the Draughts timeout behaviour.
        d.phase = "Waiting";
        d.round++;
        d.emit("TURN_PAUSED", Map.of("player", s.currentPlayer()));
        return d.build();
    }

    private void advance(WhotState.Draft d, int steps) {
        d.phase = "Turn";
        d.turnIndex = (d.turnIndex + steps) % d.players.size();
        d.round++;
        announceTurn(d);
    }

    private static boolean isPlayableTurn(String phase) {
        return "Turn".equals(phase) || "Waiting".equals(phase);
    }

    private void announceTurn(WhotState.Draft d) {
        WhotCard top = d.pile.isEmpty() ? null : d.pile.get(d.pile.size() - 1);
        d.emit("TURN_STARTED", Map.of(
                "player", d.currentPlayer(),
                "topCard", top == null ? "" : top.code(),
                "activeShape", activeShapeName(d),
                "pendingPick", d.pendingPick,
                "marketLeft", d.market.size(),
                "handSizes", handSizes(d)));
    }

    /**
     * Takes the next card off the market, turning the played pile back over
     * when it runs dry — the card in play stays where it is.
     */
    private WhotCard draw(WhotState.Draft d) {
        if (d.market.isEmpty()) {
            if (d.pile.size() <= 1) {
                throw new RuleViolation("DECK_EXHAUSTED", "there are no cards left to draw");
            }
            WhotCard top = d.pile.remove(d.pile.size() - 1);
            d.market.addAll(d.pile);
            d.pile.clear();
            d.pile.add(top);
            // Deterministic rotation rather than a reshuffle: the module has
            // no RandomSource here, and every seat has seen these cards
            // anyway.
            java.util.Collections.reverse(d.market);
        }
        return d.market.remove(d.market.size() - 1);
    }

    private boolean matches(WhotCard card, WhotState s) {
        if (card.isWhot()) {
            return true;
        }
        WhotCard top = s.topCard();
        if (top == null) {
            return true;
        }
        WhotCard.Shape want = s.activeShape();
        return card.shape() == want || card.number() == top.number();
    }

    private static boolean isSpecial(WhotCard card, WhotConfig c) {
        if (card.isWhot()) {
            return true;
        }
        return (card.number() == 2 && c.pickTwo())
                || (card.number() == 14 && c.generalMarket())
                || (card.number() == 1 && c.holdOn())
                || (card.number() == 8 && c.suspension());
    }

    private void finish(WhotState.Draft d, String winner) {
        Map<String, String> outcome = new LinkedHashMap<>();
        for (String p : d.players) {
            outcome.put(p, p.equals(winner) ? "won" : "lost");
        }
        d.win = new WinResult(winner, outcome);
        d.phase = "Results";
        d.emit("GAME_OVER", Map.of("winner", winner, "handSizes", handSizes(d)));
    }

    // ---------------------------------------------------------------- views

    @Override
    public Optional<WinResult> checkWinCondition(GameState state) {
        return Optional.ofNullable(((WhotState) state).win);
    }

    /** Your own hand, plus everything on the table. Never anyone else's cards. */
    @Override
    public PlayerVisibleState visibleStateFor(GameState state, String playerId) {
        WhotState s = (WhotState) state;
        Map<String, Object> m = commonView(s);
        m.put("yourHand", s.handOf(playerId).stream().map(WhotCard::code).toList());
        m.put("yourTurn", s.currentPlayer().equals(playerId));
        return new PlayerVisibleState(m);
    }

    /** What a spectator sees: the table, and how many cards each player holds. */
    @Override
    public PublicBroadcastState broadcastState(GameState state) {
        return new PublicBroadcastState(commonView((WhotState) state));
    }

    private Map<String, Object> commonView(WhotState s) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("phase", s.phase);
        m.put("dealer", s.players.get(0));
        m.put("suggestedHand", s.config.startingHand());
        if (s.win != null) m.put("winner", s.win.winningSide());
        m.put("round", s.round);
        m.put("players", s.players);
        m.put("turnPlayer", s.currentPlayer());
        m.put("topCard", s.topCard() == null ? "" : s.topCard().code());
        m.put("activeShape", s.activeShape() == null ? "" : s.activeShape().name().toLowerCase());
        m.put("pendingPick", s.pendingPick);
        m.put("marketLeft", s.market.size());
        m.put("handSizes", handSizesOf(s));
        m.put("rules", rulesSummary(s.config));
        return m;
    }

    private static Map<String, Integer> handSizes(WhotState.Draft d) {
        Map<String, Integer> sizes = new LinkedHashMap<>();
        d.hands.forEach((k, v) -> sizes.put(k, v.size()));
        return sizes;
    }

    private static Map<String, Integer> handSizesOf(WhotState s) {
        Map<String, Integer> sizes = new LinkedHashMap<>();
        s.hands.forEach((k, v) -> sizes.put(k, v.size()));
        return sizes;
    }

    private static String activeShapeName(WhotState.Draft d) {
        if (d.demandedShape != null) {
            return d.demandedShape.name().toLowerCase();
        }
        if (d.pile.isEmpty()) {
            return "";
        }
        return d.pile.get(d.pile.size() - 1).shape().name().toLowerCase();
    }

    private static Map<String, Object> rulesSummary(WhotConfig c) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("includeWhot", c.includeWhot());
        m.put("pickTwo", c.pickTwo());
        m.put("pickTwoStacking", c.pickTwoStacking());
        m.put("generalMarket", c.generalMarket());
        m.put("holdOn", c.holdOn());
        m.put("suspension", c.suspension());
        return m;
    }

    @Override
    public List<GameEvent> drainEvents(GameState prev, GameState next) {
        List<GameEvent> a = ((WhotState) prev).events();
        List<GameEvent> b = ((WhotState) next).events();
        return b.subList(a.size(), b.size());
    }

    // ---------------------------------------------------------------- helpers

    private static void requireTurn(WhotState s, String actor) {
        require(s.players.contains(actor), "NOT_A_PLAYER", "you're not in this game");
        require(s.currentPlayer().equals(actor), "NOT_YOUR_TURN", "it's not your turn");
    }

    private static void require(boolean ok, String code, String message) {
        if (!ok) {
            throw new RuleViolation(code, message);
        }
    }
}
