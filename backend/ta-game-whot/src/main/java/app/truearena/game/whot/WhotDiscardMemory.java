package app.truearena.game.whot;

import java.util.*;

/** Remembers only publicly observed cards still in the discard pile, including partial reconnect history. */
public final class WhotDiscardMemory {
    private final TreeMap<Integer, String> observed = new TreeMap<>();
    private int count;

    public void reset() { observed.clear(); count = 0; }

    public void observe(Map<String, Object> snapshot) {
        if (!(snapshot.get("discardCount") instanceof Number n) || !(snapshot.get("discardCards") instanceof List<?> tail)) return;
        int next = n.intValue();
        if (next < 0 || next > 1500 || tail.size() > next) { reset(); return; }
        if (next < count) observed.clear();
        int from = next - tail.size();
        for (int i = 0; i < tail.size(); i++) {
            String previous = observed.get(from + i);
            if (previous != null && !previous.equals(String.valueOf(tail.get(i)))) { observed.clear(); break; }
        }
        for (int i = 0; i < tail.size(); i++) observed.put(from + i, String.valueOf(tail.get(i)));
        count = next;
    }

    public List<String> knownCards(int maximum) {
        List<String> cards = new ArrayList<>(observed.values());
        return List.copyOf(maximum > 0 && cards.size() > maximum ? cards.subList(cards.size() - maximum, cards.size()) : cards);
    }
}
