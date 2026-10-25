package app.truearena.game.ludo;

import app.truearena.engine.PlayerAction;

import java.util.*;

/** Probability-weighted dice search. Players maximise their own utility; no server seed is accepted. */
public final class LudoExpectimaxSearch {
    private static final LudoModule GAME = new LudoModule();
    private static final Set<Integer> SAFE = Set.of(0, 8, 13, 21, 26, 34, 39, 47);

    public record Limits(int rolls, int futureWidth, int nodes, long millis) {
        public Limits {
            if (rolls < 0 || rolls > 3 || futureWidth < 1 || futureWidth > 8 || nodes < 1 || nodes > 100000
                    || millis < 1 || millis > 1000) throw new IllegalArgumentException("Invalid expectimax limits");
        }
    }

    public record Decision(Optional<PlayerAction> action, int completedRollHorizon, int nodes, int chanceOutcomes,
                           double expectedUtility) {}
    private record Branch(PlayerAction action, LudoState state, double priority) {}
    private record Key(List<List<Integer>> pieces, List<Integer> dice, int turn, int bonus,
                       Set<String> eliminated, int rolls, boolean knownDice) {}

    private final Limits limits;
    private final long deadline;
    private final Map<Key, double[]> cache = new HashMap<>();
    private int nodes;
    private int chanceOutcomes;

    private LudoExpectimaxSearch(Limits limits) {
        this.limits = limits;
        deadline = System.nanoTime() + limits.millis() * 1_000_000;
    }

    public static Decision choose(Map<String, Object> view, String player, Limits limits) {
        Optional<LudoState> parsed = fromView(view, player);
        if (parsed.isEmpty()) return new Decision(Optional.empty(), -1, 0, 0, 0);
        LudoState root = parsed.get();
        if (root.dice().isEmpty()) return new Decision(Optional.of(PlayerAction.of(player, "ROLL", Map.of())), 0, 0, 0, 0);
        var search = new LudoExpectimaxSearch(limits);
        List<Branch> branches = search.branches(root);
        if (branches.isEmpty()) return new Decision(Optional.empty(), -1, 0, 0, 0);
        PlayerAction best = branches.getFirst().action();
        int seat = root.turnIndex(), completed = -1;
        double expected = branches.getFirst().priority();
        for (int horizon = 0; horizon <= limits.rolls(); horizon++) {
            try {
                double highest = Double.NEGATIVE_INFINITY;
                PlayerAction candidate = best;
                for (Branch branch : branches) {
                    double score = search.visit(branch.state(), horizon, true)[seat];
                    if (score > highest) { highest = score; candidate = branch.action(); }
                }
                // Partial chance averages or partial root comparisons never replace a completed result.
                completed = horizon;
                best = candidate;
                expected = highest;
            } catch (Exhausted ignored) { break; }
        }
        return new Decision(Optional.of(PlayerAction.of(player, best.type(), best.data())), completed, search.nodes, search.chanceOutcomes, expected);
    }

    /** Reconstruct only visible fields. Seed, future rolls, undo history and action IDs are intentionally ignored. */
    static Optional<LudoState> fromView(Map<String, Object> view, String player) {
        if (!(view.get("players") instanceof List<?> ps) || !(view.get("pieces") instanceof Map<?, ?> raw)
                || !(view.get("dice") instanceof List<?> ds) || !player.equals(view.get("turnPlayer"))) return Optional.empty();
        try {
            List<String> players = ps.stream().map(String::valueOf).toList();
            if (players.size() < 2 || players.size() > 4 || new HashSet<>(players).size() != players.size()
                    || !players.contains(player)) return Optional.empty();
            Map<String, List<Integer>> pieces = new LinkedHashMap<>();
            int size = -1;
            for (String p : players) {
                if (!(raw.get(p) instanceof List<?> list)) return Optional.empty();
                List<Integer> positions = list.stream().map(LudoExpectimaxSearch::number).toList();
                if ((positions.size() != 4 && !(players.size() == 2 && positions.size() == 8))
                        || positions.stream().anyMatch(n -> n < -1 || n > 56) || (size != -1 && size != positions.size()))
                    return Optional.empty();
                size = positions.size(); pieces.put(p, positions);
            }
            List<Integer> dice = ds.stream().map(LudoExpectimaxSearch::number).toList();
            if (dice.size() > 2 || dice.stream().anyMatch(n -> n < 1 || n > 6)) return Optional.empty();
            Set<String> eliminated = new HashSet<>();
            if (view.get("eliminated") instanceof Collection<?> list) list.forEach(p -> eliminated.add(String.valueOf(p)));
            if (!players.containsAll(eliminated) || eliminated.contains(player)) return Optional.empty();
            int bonus = view.get("bonusRolls") instanceof Number n ? n.intValue() : 0;
            if (bonus < 0 || bonus > 1) return Optional.empty();
            return Optional.of(new LudoState("Turn", 1, players, pieces, players.indexOf(player), dice, 0, bonus, 0,
                    null, eliminated, Set.of(), List.of(), new LudoConfig(60, size)));
        } catch (IllegalArgumentException e) { return Optional.empty(); }
    }

    private double[] visit(LudoState state, int rolls, boolean knownDice) {
        check(); nodes++;
        if (state.finished() || (state.dice().isEmpty() && rolls == 0)) return evaluate(state);
        Key key = key(state, rolls, knownDice);
        double[] cached = cache.get(key);
        if (cached != null) return cached;
        double[] result;
        if (state.dice().isEmpty()) {
            result = new double[state.players().size()];
            // Unordered pairs cover all 36 equally likely ordered outcomes: doubles weigh 1, others 2.
            for (int first = 1; first <= 6; first++) for (int second = first; second <= 6; second++) {
                check(); chanceOutcomes++;
                LudoState rolled = compact(GAME.applyRolledDice(state, "simulation", List.of(first, second)));
                double[] value = visit(rolled, rolls - 1, false);
                double probability = (first == second ? 1.0 : 2.0) / 36;
                for (int i = 0; i < result.length; i++) result[i] += probability * value[i];
            }
        } else {
            List<Branch> branches = branches(state);
            if (branches.isEmpty()) return evaluate(state);
            int actor = state.turnIndex();
            result = null;
            int width = knownDice ? branches.size() : Math.min(limits.futureWidth(), branches.size());
            for (int i = 0; i < width; i++) {
                double[] value = visit(branches.get(i).state(), rolls, knownDice);
                if (result == null || value[actor] > result[actor]) result = value;
            }
        }
        cache.put(key, result);
        return result;
    }

    private List<Branch> branches(LudoState state) {
        List<Branch> result = new ArrayList<>();
        for (PlayerAction move : GAME.searchMoves(state)) {
            LudoState after = compact((LudoState) GAME.onPlayerAction(state, move));
            result.add(new Branch(move, after, evaluate(after)[state.turnIndex()]));
        }
        result.sort(Comparator.comparingDouble(Branch::priority).reversed());
        return result;
    }

    private static double[] evaluate(LudoState state) {
        int count = state.players().size();
        double[] own = new double[count], values = new double[count];
        for (int i = 0; i < count; i++) {
            String player = state.players().get(i);
            if (state.finished()) { values[i] = player.equals(state.winner()) ? 100000 : -100000; continue; }
            if (state.eliminated().contains(player)) { own[i] = -10000; continue; }
            for (int position : state.pieces().get(player)) {
                if (position == 56) { own[i] += 200; continue; }
                if (position < 0) { own[i] -= 10; continue; }
                if (position > 50) { own[i] += 90 + (position - 50) * 6; continue; }
                own[i] += 20 + position;
                int square = square(state, i, position);
                if (SAFE.contains(square)) own[i] += 12;
                else {
                    for (int j = 0; j < count; j++) {
                        if (i == j || state.eliminated().contains(state.players().get(j))) continue;
                        for (int other : state.pieces().get(state.players().get(j))) {
                            if (other < 0 || other > 50) continue;
                            int distance = Math.floorMod(square - square(state, j, other), 52);
                            if (distance > 0 && distance <= 6 && other + distance <= 50) own[i] -= 8 + position * .2;
                        }
                    }
                }
            }
        }
        if (state.finished()) return values;
        for (int i = 0; i < count; i++) {
            double opponents = 0; int active = 0;
            for (int j = 0; j < count; j++) if (j != i && !state.eliminated().contains(state.players().get(j))) {
                opponents += own[j]; active++;
            }
            values[i] = own[i] - .6 * opponents / Math.max(1, active);
        }
        return values;
    }

    private static int square(LudoState state, int seat, int progress) {
        return ((state.players().size() == 2 ? seat * 2 : seat) * 13 + progress) % 52;
    }

    private static Key key(LudoState state, int rolls, boolean knownDice) {
        return new Key(state.players().stream().map(p -> state.pieces().get(p).stream().sorted().toList()).toList(),
                state.dice().stream().sorted().toList(), state.turnIndex(), state.bonusRolls(), state.eliminated(), rolls, knownDice);
    }

    private static LudoState compact(LudoState state) {
        return new LudoState(state.phase(), 1, state.players(), state.pieces(), state.turnIndex(), state.dice(), 0,
                state.bonusRolls(), 0, state.winner(), state.eliminated(), Set.of(), List.of(), state.config());
    }

    private void check() {
        if (nodes >= limits.nodes() || System.nanoTime() >= deadline || Thread.currentThread().isInterrupted()) throw new Exhausted();
    }
    private static int number(Object value) { return value instanceof Number n ? n.intValue() : -2; }
    private static final class Exhausted extends RuntimeException { Exhausted() { super(null, null, false, false); } }
}
