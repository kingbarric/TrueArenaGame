package app.truearena.game.whot;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.WinResult;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Immutable snapshot of a Whot game. Built only via {@link Draft}, same
 * convention as the other modules.
 *
 * <p>Hands are the secret here — everything else on the table is open. A
 * player may see their own cards and everyone else's <em>count</em>, never
 * anyone else's cards: see {@code WhotModule.visibleStateFor}.
 */
public final class WhotState implements GameState {

    final String phase;
    final int round;
    final List<String> players;

    /** Each player's hand. The one piece of hidden information in the game. */
    final Map<String, List<WhotCard>> hands;

    /** Face-down draw pile. The last element is the next card out. */
    final List<WhotCard> market;

    /** Face-up discard pile. The last element is the card in play. */
    final List<WhotCard> pile;

    /** Set while a Whot card is in play — the shape its holder called for. */
    final WhotCard.Shape demandedShape;

    /** Cards the next player owes, accumulated by twos. Zero when nothing is pending. */
    final int pendingPick;

    final int turnIndex;
    final WhotConfig config;
    final Set<String> appliedActionIds;
    final List<GameEvent> events;
    final long seq;
    final WinResult win;

    private WhotState(Draft d) {
        this.phase = d.phase;
        this.round = d.round;
        this.players = List.copyOf(d.players);
        Map<String, List<WhotCard>> copied = new LinkedHashMap<>();
        d.hands.forEach((k, v) -> copied.put(k, List.copyOf(v)));
        this.hands = Map.copyOf(copied);
        this.market = List.copyOf(d.market);
        this.pile = List.copyOf(d.pile);
        this.demandedShape = d.demandedShape;
        this.pendingPick = d.pendingPick;
        this.turnIndex = d.turnIndex;
        this.config = d.config;
        this.appliedActionIds = Set.copyOf(d.appliedActionIds);
        this.events = List.copyOf(d.events);
        this.seq = d.seq;
        this.win = d.win;
    }

    @Override public String phase() { return phase; }
    @Override public int round() { return round; }
    @Override public boolean finished() { return "Results".equals(phase); }
    @Override public List<GameEvent> events() { return events; }

    String currentPlayer() {
        return players.get(turnIndex % players.size());
    }

    /** The card everyone is matching against. */
    WhotCard topCard() {
        return pile.isEmpty() ? null : pile.get(pile.size() - 1);
    }

    /**
     * The shape a play has to match: whatever was called on a Whot card, or
     * else the top card's own shape.
     */
    WhotCard.Shape activeShape() {
        if (demandedShape != null) {
            return demandedShape;
        }
        WhotCard top = topCard();
        return top == null ? null : top.shape();
    }

    List<WhotCard> handOf(String playerId) {
        return hands.getOrDefault(playerId, List.of());
    }

    /** Mutable builder — the only way to derive a new {@link WhotState}. */
    static final class Draft {
        String phase = "Turn";
        int round = 1;
        List<String> players = new ArrayList<>();
        Map<String, List<WhotCard>> hands = new LinkedHashMap<>();
        List<WhotCard> market = new ArrayList<>();
        List<WhotCard> pile = new ArrayList<>();
        WhotCard.Shape demandedShape;
        int pendingPick;
        int turnIndex;
        WhotConfig config;
        Set<String> appliedActionIds = new LinkedHashSet<>();
        List<GameEvent> events = new ArrayList<>();
        long seq;
        WinResult win;

        Draft() {
        }

        Draft(WhotState s) {
            this.phase = s.phase;
            this.round = s.round;
            this.players = new ArrayList<>(s.players);
            s.hands.forEach((k, v) -> this.hands.put(k, new ArrayList<>(v)));
            this.market = new ArrayList<>(s.market);
            this.pile = new ArrayList<>(s.pile);
            this.demandedShape = s.demandedShape;
            this.pendingPick = s.pendingPick;
            this.turnIndex = s.turnIndex;
            this.config = s.config;
            this.appliedActionIds = new LinkedHashSet<>(s.appliedActionIds);
            this.events = new ArrayList<>(s.events);
            this.seq = s.seq;
            this.win = s.win;
        }

        WhotState build() {
            return new WhotState(this);
        }

        void emit(String type, Map<String, Object> payload) {
            events.add(GameEvent.pub(++seq, type, payload));
        }

        void emitToPlayer(String type, Map<String, Object> payload, String playerId) {
            events.add(GameEvent.toPlayer(++seq, type, payload, playerId));
        }

        String currentPlayer() {
            return players.get(turnIndex % players.size());
        }
    }
}
