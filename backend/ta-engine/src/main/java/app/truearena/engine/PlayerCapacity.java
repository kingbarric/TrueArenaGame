package app.truearena.engine;

import java.util.List;

/** Authoritative roster limits exposed by the game, including mode-specific seat counts. */
public record PlayerCapacity(int min, int max, List<Integer> allowed) {
    public PlayerCapacity(int min, int max) { this(min,max,List.of()); }
    public boolean accepts(int count) {
        return count >= min && count <= max && (allowed.isEmpty() || allowed.contains(count));
    }
}
