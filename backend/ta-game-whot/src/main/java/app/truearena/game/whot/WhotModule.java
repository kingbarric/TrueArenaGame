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
import java.util.Set;

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
    private static final Set<String> TELL_SYMBOLS = Set.of(
            "🪐", "🌌", "☄️", "🌠", "🌑", "🌒", "🌓", "🌔", "🌕", "🌘",
            "🌙", "🌚", "🌝", "✨", "🔮", "🧿", "🗝️", "🪬", "🕯️", "🪞",
            "🪄", "🕳️", "🛸", "👁️", "🗿", "🧬", "🌀", "⚗️", "💠", "🧩");

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
                Phase.untimed("Signals"),
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
        if (config.tell() && playerIds.size() != 4 && playerIds.size() != 6 && playerIds.size() != 8) {
            throw new RuleViolation("BAD_PLAYER_COUNT", "The Tell needs 4, 6, or 8 players");
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
        d.phase = config.tell() ? "Signals" : "Deal";
        if (config.tell()) {
            for (int i = 0; i < playerIds.size(); i += 2) {
                d.teams.add(List.of(playerIds.get(i), playerIds.get(i + 1)));
            }
            d.stage = d.teams.size() == 2 ? "final" : "qualification";
        }

        d.emit("GAME_STARTED", Map.of(
                "players", List.copyOf(playerIds),
                "dealer", playerIds.get(0),
                "suggestedHand", config.startingHand(),
                "turnSeconds", config.turnSeconds(),
                "mode", config.mode(),
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
            case "CHOOSE_SIGNAL" -> chooseSignal(d, s, action);
            case "SIGNAL" -> displaySignal(d, s, action);
            case "BUZZ" -> buzz(d, s, action);
            case "FORFEIT" -> forfeit(d, s, action);
            default -> throw new RuleViolation("UNKNOWN_ACTION", "no handler for " + action.type());
        }
        return d.build();
    }

    /** Whoever sits first deals — they shuffle, deal, and call the start. */
    private static String dealerOf(WhotState s) {
        if (!s.config.tell()) return s.players.get(0);
        return s.players.stream().filter(p -> active(s, p)).findFirst().orElse(s.players.get(0));
    }

    private static int teamOf(WhotState s, String player) {
        for (int i = 0; i < s.teams.size(); i++) {
            if (s.teams.get(i).contains(player)) return i;
        }
        return -1;
    }

    private static int teamOf(WhotState.Draft d, String player) {
        for (int i = 0; i < d.teams.size(); i++) {
            if (d.teams.get(i).contains(player)) return i;
        }
        return -1;
    }

    private static boolean active(WhotState s, String player) {
        int team = teamOf(s, player);
        return team >= 0 && !s.qualifiedTeams.contains(team) && !s.eliminatedTeams.contains(team);
    }

    private static boolean active(WhotState.Draft d, String player) {
        int team = teamOf(d, player);
        return team >= 0 && !d.qualifiedTeams.contains(team) && !d.eliminatedTeams.contains(team);
    }

    private static List<String> activePlayers(WhotState.Draft d) {
        return d.players.stream().filter(p -> !d.config.tell() || active(d, p)).toList();
    }

    private static void requireDealing(WhotState s, String actor) {
        require("Deal".equals(s.phase), "WRONG_PHASE", "the cards are already out");
        require(actor.equals(dealerOf(s)), "NOT_THE_DEALER", "only the dealer handles the cards");
    }

    private void chooseSignal(WhotState.Draft d, WhotState s, PlayerAction a) {
        require(s.config.tell() && "Signals".equals(s.phase), "WRONG_PHASE", "signals are not being chosen");
        require(active(s, a.actor()), "NOT_ACTIVE", "your team is not in this round");
        String symbol = String.valueOf(a.data().get("symbol"));
        require(TELL_SYMBOLS.contains(symbol), "BAD_SIGNAL", "choose a symbol from the signal tray");
        int team = teamOf(s, a.actor());
        String previous = d.teamSignals.put(team, symbol);
        if (previous != null && !previous.equals(symbol)) {
            d.signalConfirmed.removeAll(d.teams.get(team));
        }
        d.signalConfirmed.add(a.actor());
        d.emit("SIGNAL_CONFIRMED", Map.of("team", team, "ready", d.teams.get(team).stream()
                .filter(d.signalConfirmed::contains).count()));
        if (activePlayers(d).stream().allMatch(d.signalConfirmed::contains)) {
            d.phase = "Deal";
            d.emit("SIGNALS_READY", Map.of("stage", d.stage));
        }
    }

    private void displaySignal(WhotState.Draft d, WhotState s, PlayerAction a) {
        require(s.config.tell() && isPlayableTurn(s.phase), "WRONG_PHASE", "signals require active play");
        require(active(s, a.actor()), "NOT_ACTIVE", "your team is not in this round");
        String symbol = String.valueOf(a.data().get("symbol"));
        require(TELL_SYMBOLS.contains(symbol), "BAD_SIGNAL", "choose a symbol from the signal tray");
        d.signalId = d.seq + 1;
        d.signalBy = a.actor();
        d.signalSymbol = symbol;
        d.signalSentAtMs = System.currentTimeMillis();
        d.signalValid = hasSet(d.hands.get(a.actor()), d.config);
        d.signalOpen = true;
        d.emit("SIGNAL_DISPLAYED", Map.of("id", d.signalId, "by", a.actor(),
                "symbol", symbol, "sentAtMs", d.signalSentAtMs));
    }

    /** Every remaining card must share one value or one printed shape. */
    private static boolean hasSet(List<WhotCard> hand, WhotConfig config) {
        if (hand == null || hand.size() < config.tellMinCards()) return false;
        boolean sameValue = hand.stream().allMatch(card -> card.number() == hand.get(0).number());
        boolean sameShape = hand.stream().allMatch(card -> card.shape() == hand.get(0).shape());
        return switch (config.tellRule()) {
            case "value" -> sameValue;
            case "shape" -> sameShape;
            default -> sameValue || sameShape;
        };
    }

    private void protectInitialTellDeal(WhotState.Draft d) {
        if (!d.config.tell()) return;
        List<String> recipients = activePlayers(d);
        if (recipients.stream().noneMatch(p -> hasSet(d.hands.get(p), d.config))) return;
        int handSize = d.hands.get(recipients.get(0)).size();
        List<WhotCard> completeDeck = new ArrayList<>(d.market);
        for (String p : recipients) {
            completeDeck.addAll(d.hands.get(p));
            d.hands.get(p).clear();
        }
        for (int attempt = 1; attempt <= 1000; attempt++) {
            shuffle(completeDeck, RandomSource.seeded(java.util.concurrent.ThreadLocalRandom.current().nextLong()));
            for (String p : recipients) d.hands.get(p).clear();
            int at = completeDeck.size() - 1;
            for (int round = 0; round < handSize; round++) {
                for (String p : recipients) d.hands.get(p).add(completeDeck.get(at--));
            }
            if (recipients.stream().noneMatch(p -> hasSet(d.hands.get(p), d.config))) {
                d.market = new ArrayList<>(completeDeck.subList(0, at + 1));
                d.emit("DEAL_RESHUFFLED", Map.of("attempts", attempt, "marketLeft", d.market.size(),
                        "handSizes", handSizes(d)));
                for (String p : recipients) {
                    d.emitToPlayer("YOUR_HAND", Map.of("cards", d.hands.get(p).stream().map(WhotCard::code).toList()), p);
                }
                return;
            }
        }
        throw new RuleViolation("NO_FAIR_DEAL", "could not make a starting deal without an immediate Tell");
    }

    private void buzz(WhotState.Draft d, WhotState s, PlayerAction a) {
        require(s.config.tell() && isPlayableTurn(s.phase), "WRONG_PHASE", "there is no live signal");
        require(active(s, a.actor()), "NOT_ACTIVE", "your team is not in this round");
        long id = a.data().get("signalId") instanceof Number n ? n.longValue() : -1;
        require(s.signalOpen && id == s.signalId && System.currentTimeMillis() - s.signalSentAtMs <= 3000,
                "SIGNAL_CLOSED", "that signal can no longer be buzzed");
        require(!a.actor().equals(s.signalBy), "OWN_SIGNAL", "you cannot buzz your own signal");
        int callerTeam = teamOf(s, a.actor());
        int senderTeam = teamOf(s, s.signalBy);
        boolean correct = s.signalValid && s.signalSymbol.equals(s.teamSignals.get(senderTeam));
        d.signalOpen = false;
        d.emit("BUZZ_RESOLVED", Map.of("by", a.actor(), "sender", s.signalBy,
                "signalId", id, "correct", correct, "interception", callerTeam != senderTeam,
                "team", callerTeam, "receivedAtMs", System.currentTimeMillis()));
        if (correct) qualifyTeam(d, callerTeam);
        else eliminateTeam(d, callerTeam);
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
        List<String> recipients = activePlayers(d);
        int rounds = a.data().get("rounds") instanceof Number n ? n.intValue() : 1;
        require(rounds >= 1 && rounds <= 12, "BAD_DEAL", "deal between 1 and 12 rounds at a time");

        for (int r = 0; r < rounds; r++) {
            require(d.market.size() >= recipients.size() + MARKET_HEADROOM / 2,
                    "NOT_ENOUGH_CARDS", "not enough cards left to deal another round");
            for (String p : recipients) {
                d.hands.get(p).add(d.market.remove(d.market.size() - 1));
            }
        }
        d.emit("CARDS_DEALT", Map.of(
                "by", a.actor(), "rounds", rounds,
                "marketLeft", d.market.size(), "handSizes", handSizes(d)));
        for (String p : recipients) {
            d.emitToPlayer("YOUR_HAND",
                    Map.of("cards", d.hands.get(p).stream().map(WhotCard::code).toList()), p);
        }
    }

    /** Ends the deal and turns the first card over. */
    private void startAction(WhotState.Draft d, WhotState s, PlayerAction a) {
        requireDealing(s, a.actor());
        for (String p : activePlayers(d)) {
            require(d.hands.get(p).size() >= MIN_HAND, "DEAL_FIRST",
                    "everyone needs at least " + MIN_HAND + " cards");
        }
        protectInitialTellDeal(d);
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
            if (d.config.tell()) qualifyTeam(d, teamOf(d, a.actor()));
            else finish(d, a.actor());
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
            for (String p : activePlayers(d)) {
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
        if (s.config.tell()) {
            require(active(s, a.actor()), "NOT_ACTIVE", "your team is not in this round");
            d.emit("PLAYER_FORFEITED", Map.of("player", a.actor()));
            eliminateTeam(d, teamOf(s, a.actor()));
            return;
        }
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
            List<String> recipients = activePlayers(d);
            while (d.hands.get(recipients.get(0)).size() < d.config.startingHand()
                    && d.market.size() >= recipients.size() + MARKET_HEADROOM / 2) {
                for (String p : recipients) {
                    d.hands.get(p).add(d.market.remove(d.market.size() - 1));
                }
            }
            protectInitialTellDeal(d);
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
        for (int i = 0; i < steps; i++) {
            do {
                d.turnIndex = (d.turnIndex + 1) % d.players.size();
            } while (d.config.tell() && !active(d, d.currentPlayer()));
        }
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

    /** Takes the next card in the existing shuffled order. */
    private WhotCard draw(WhotState.Draft d) {
        if (d.market.isEmpty()) {
            recycleDiscard(d);
        }
        WhotCard next = d.market.remove(d.market.size() - 1);
        // Rebuild the face-down stack as soon as its last card is taken, so
        // the table sees the discard cards move back before the next turn.
        if (d.market.isEmpty() && d.pile.size() > 1) {
            recycleDiscard(d);
        }
        return next;
    }

    /** Shuffle played cards back into the market while keeping its top in play. */
    private void recycleDiscard(WhotState.Draft d) {
        if (d.pile.size() <= 1) {
            throw new RuleViolation("DECK_EXHAUSTED", "there are no cards left to draw");
        }
        WhotCard top = d.pile.remove(d.pile.size() - 1);
        d.market.addAll(d.pile);
        d.pile.clear();
        d.pile.add(top);
        // Derive a reproducible cut from the hidden card order and event
        // sequence, so replaying the same game state gives the same result.
        long seed = 31L * d.seq + d.market.hashCode();
        shuffle(d.market, RandomSource.seeded(seed));
        d.emit("MARKET_RESHUFFLED", Map.of(
                "marketLeft", d.market.size(), "discardCount", d.pile.size()));
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

    private void finishTeam(WhotState.Draft d, int winnerTeam) {
        Map<String, String> outcome = new LinkedHashMap<>();
        for (String p : d.players) {
            outcome.put(p, teamOf(d, p) == winnerTeam ? "won" : "lost");
        }
        d.win = new WinResult("team-" + winnerTeam, outcome);
        d.phase = "Results";
        d.signalOpen = false;
        d.emit("GAME_OVER", Map.of("winner", d.teams.get(winnerTeam).get(0),
                "winnerTeam", winnerTeam, "handSizes", handSizes(d)));
    }

    private void qualifyTeam(WhotState.Draft d, int team) {
        if ("final".equals(d.stage)) {
            finishTeam(d, team);
            return;
        }
        if (!d.qualifiedTeams.contains(team)) d.qualifiedTeams.add(team);
        d.signalOpen = false;
        d.emit("TEAM_QUALIFIED", Map.of("team", team, "qualified", List.copyOf(d.qualifiedTeams)));
        if (d.qualifiedTeams.size() >= 2) {
            startFinal(d);
        } else if (!active(d, d.currentPlayer())) {
            advance(d, 1);
        }
    }

    private void eliminateTeam(WhotState.Draft d, int team) {
        if (!d.eliminatedTeams.contains(team)) d.eliminatedTeams.add(team);
        d.signalOpen = false;
        d.emit("TEAM_ELIMINATED", Map.of("team", team, "eliminated", List.copyOf(d.eliminatedTeams)));
        if ("final".equals(d.stage)) {
            int winner = -1;
            for (int i = 0; i < d.teams.size(); i++) {
                if (i != team && !d.eliminatedTeams.contains(i)) winner = i;
            }
            if (winner >= 0) finishTeam(d, winner);
            return;
        }
        List<Integer> remaining = new ArrayList<>();
        for (int i = 0; i < d.teams.size(); i++) {
            if (!d.qualifiedTeams.contains(i) && !d.eliminatedTeams.contains(i)) remaining.add(i);
        }
        if (remaining.size() == 1 && d.qualifiedTeams.size() == 1) {
            d.qualifiedTeams.add(remaining.get(0));
            d.emit("TEAM_QUALIFIED", Map.of("team", remaining.get(0), "qualified", List.copyOf(d.qualifiedTeams)));
            startFinal(d);
        } else if (remaining.isEmpty() && d.qualifiedTeams.size() == 1) {
            finishTeam(d, d.qualifiedTeams.get(0));
        } else if (remaining.size() == 1 && d.qualifiedTeams.isEmpty()) {
            finishTeam(d, remaining.get(0));
        } else if (!active(d, d.currentPlayer())) {
            advance(d, 1);
        }
    }

    private void startFinal(WhotState.Draft d) {
        List<Integer> finalists = List.copyOf(d.qualifiedTeams);
        for (int i = 0; i < d.teams.size(); i++) {
            if (!finalists.contains(i) && !d.eliminatedTeams.contains(i)) d.eliminatedTeams.add(i);
        }
        d.qualifiedTeams.clear();
        d.teamSignals.clear();
        d.signalConfirmed.clear();
        d.signalOpen = false;
        d.signalBy = null;
        d.signalSymbol = null;
        d.stage = "final";
        d.phase = "Signals";
        d.pendingPick = 0;
        d.demandedShape = null;
        d.pile.clear();
        d.hands.values().forEach(List::clear);
        d.market = buildDeck(d.config, 4);
        shuffle(d.market, RandomSource.seeded(java.util.concurrent.ThreadLocalRandom.current().nextLong()));
        d.turnIndex = d.players.indexOf(activePlayers(d).get(0));
        d.round++;
        d.emit("FINAL_STARTED", Map.of("teams", finalists, "marketLeft", d.market.size()));
    }

    // ---------------------------------------------------------------- views

    @Override
    public Optional<WinResult> checkWinCondition(GameState state) {
        return Optional.ofNullable(((WhotState) state).win);
    }

    @Override
    public java.util.Set<String> playersToAct(GameState state) {
        WhotState s = (WhotState) state;
        // The optional "call GAME" signal (signalConfirmed) is a voluntary,
        // anytime declaration, not a gate on whose turn it is to play a card
        // — currentPlayer() alone is the one actually blocking progress.
        if (s.finished()) return java.util.Set.of();
        return java.util.Set.of(s.currentPlayer());
    }

    /** Your own hand, plus everything on the table. Never anyone else's cards. */
    @Override
    public PlayerVisibleState visibleStateFor(GameState state, String playerId) {
        WhotState s = (WhotState) state;
        Map<String, Object> m = commonView(s);
        m.put("yourHand", s.handOf(playerId).stream().map(WhotCard::code).toList());
        m.put("yourTurn", s.currentPlayer().equals(playerId));
        if (s.config.tell()) {
            int team = teamOf(s, playerId);
            if (team >= 0) {
                m.put("yourTeam", team);
                m.put("yourSignal", s.teamSignals.getOrDefault(team, ""));
                m.put("yourSignalConfirmed", s.signalConfirmed.contains(playerId));
                m.put("partnerSignalConfirmed", s.teams.get(team).stream()
                        .filter(p -> !p.equals(playerId)).anyMatch(s.signalConfirmed::contains));
            }
        }
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
        if (s.win != null) {
            if (s.config.tell()) {
                int team = Integer.parseInt(s.win.winningSide().substring("team-".length()));
                m.put("winner", s.teams.get(team).get(0));
                m.put("winnerTeam", team);
            } else m.put("winner", s.win.winningSide());
        }
        m.put("mode", s.config.mode());
        if (s.config.tell()) {
            m.put("stage", s.stage);
            m.put("teams", s.teams);
            m.put("qualifiedTeams", s.qualifiedTeams);
            m.put("eliminatedTeams", s.eliminatedTeams);
            if (s.signalOpen) {
                m.put("signal", Map.of("id", s.signalId, "by", s.signalBy,
                        "symbol", s.signalSymbol, "sentAtMs", s.signalSentAtMs));
            }
        }
        m.put("round", s.round);
        m.put("players", s.players);
        m.put("turnPlayer", s.currentPlayer());
        m.put("topCard", s.topCard() == null ? "" : s.topCard().code());
        m.put("activeShape", s.activeShape() == null ? "" : s.activeShape().name().toLowerCase());
        m.put("pendingPick", s.pendingPick);
        m.put("marketLeft", s.market.size());
        m.put("discardCount", s.pile.size());
        m.put("discardCards", s.pile.subList(Math.max(0, s.pile.size() - 3), s.pile.size())
                .stream().map(WhotCard::code).toList());
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
