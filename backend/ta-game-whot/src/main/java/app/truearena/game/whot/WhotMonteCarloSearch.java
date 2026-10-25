package app.truearena.game.whot;

import app.truearena.engine.PlayerAction;
import app.truearena.engine.RuleViolation;

import java.util.*;

/** Flat Monte Carlo over sampled deals, constructed exclusively from a player's visible information. */
public final class WhotMonteCarloSearch {
    private static final WhotModule GAME = new WhotModule();
    private static final List<WhotCard.Shape> SHAPES = List.of(WhotCard.Shape.CIRCLE, WhotCard.Shape.TRIANGLE,
            WhotCard.Shape.CROSS, WhotCard.Shape.SQUARE, WhotCard.Shape.STAR);

    public record Limits(int samples, int plies, int transitions, long millis) {
        public Limits {
            if (samples < 1 || samples > 128 || plies < 1 || plies > 100 || transitions < 1 || transitions > 100000
                    || millis < 1 || millis > 1000) throw new IllegalArgumentException("Invalid rollout limits");
        }
    }

    public record TellTable(List<List<String>> teams, List<Integer> qualified, List<Integer> eliminated, String stage) {
        public TellTable {
            teams = teams.stream().map(List::copyOf).toList();
            qualified = List.copyOf(qualified); eliminated = List.copyOf(eliminated);
        }
    }

    public record Decision(Optional<PlayerAction> action, int completedSamples, int transitions) {}

    /** Only allowlisted fields are read: never accepts a server WhotState, other hands or a deck order. */
    public record Observation(List<String> players, List<WhotCard> hand, Map<String, Integer> handSizes,
                              List<WhotCard> knownDiscards, int discardCount, int marketLeft,
                              WhotCard top, WhotCard.Shape activeShape, int pendingPick, WhotConfig config, TellTable tell) {
        public Observation {
            players = List.copyOf(players); hand = List.copyOf(hand); handSizes = Map.copyOf(handSizes);
            knownDiscards = List.copyOf(knownDiscards);
        }

        public static Optional<Observation> fromView(Map<String, Object> view, List<String> discards, String player) {
            String mode = String.valueOf(view.getOrDefault("mode", "classic"));
            if (!List.of("classic", "tell").contains(mode)) return Optional.empty();
            if (!(view.get("players") instanceof List<?> ps) || !(view.get("yourHand") instanceof List<?> cards)
                    || !(view.get("handSizes") instanceof Map<?, ?> sizes) || !player.equals(view.get("turnPlayer")))
                return Optional.empty();
            try {
                List<String> players = ps.stream().map(String::valueOf).toList();
                if (players.size() < 2 || players.size() > 20 || new HashSet<>(players).size() != players.size()
                        || !players.contains(player)) return Optional.empty();
                List<WhotCard> hand = cards.stream().map(c -> WhotCard.parse(String.valueOf(c))).toList();
                Map<String, Integer> counts = new LinkedHashMap<>();
                for (String p : players) {
                    int count = number(sizes.get(p));
                    if (count < ("tell".equals(mode) ? 0 : 1) || count > 1000) return Optional.empty();
                    counts.put(p, count);
                }
                if (hand.isEmpty() || counts.get(player) != hand.size()) return Optional.empty();
                Map<?, ?> rules = view.get("rules") instanceof Map<?, ?> r ? r : Map.of();
                var config = new WhotConfig(60, 5, on(rules, "includeWhot"), on(rules, "pickTwo"),
                        on(rules, "pickTwoStacking"), on(rules, "generalMarket"), on(rules, "holdOn"), on(rules, "suspension"), mode,
                        rules.get("tellRule") instanceof String rule ? rule : "either",
                        rules.get("tellMinCards") instanceof Number minimum ? minimum.intValue() : 3);
                TellTable tell = null;
                if (config.tell()) {
                    if (!(view.get("teams") instanceof List<?> rawTeams)) return Optional.empty();
                    List<List<String>> teams = new ArrayList<>();
                    for (Object raw : rawTeams) {
                        if (!(raw instanceof List<?> pair) || pair.size() != 2) return Optional.empty();
                        teams.add(pair.stream().map(String::valueOf).toList());
                    }
                    List<String> seats = teams.stream().flatMap(List::stream).toList();
                    if (teams.size() < 2 || teams.size() > 4 || seats.size() != players.size()
                            || !new HashSet<>(seats).equals(new HashSet<>(players))) return Optional.empty();
                    List<Integer> qualified = indices(view.get("qualifiedTeams"));
                    List<Integer> eliminated = indices(view.get("eliminatedTeams"));
                    if (java.util.stream.Stream.concat(qualified.stream(), eliminated.stream())
                            .anyMatch(i -> i < 0 || i >= teams.size())) return Optional.empty();
                    int mine = -1;
                    for (int i = 0; i < teams.size(); i++) if (teams.get(i).contains(player)) mine = i;
                    if (qualified.contains(mine) || eliminated.contains(mine)) return Optional.empty();
                    String stage = String.valueOf(view.get("stage"));
                    if (!List.of("final", "qualification").contains(stage)) return Optional.empty();
                    tell = new TellTable(teams, qualified, eliminated, stage);
                }
                WhotCard top = WhotCard.parse(String.valueOf(view.get("topCard")));
                var active = WhotCard.Shape.valueOf(String.valueOf(view.get("activeShape")).toUpperCase(Locale.ROOT));
                int discardCount = number(view.get("discardCount")), market = number(view.get("marketLeft"));
                int pending = number(view.get("pendingPick"));
                if (discardCount < 1 || discardCount > 1500 || market < 0 || market > 1500 || pending < 0 || pending > 1500
                        || active == WhotCard.Shape.WHOT) return Optional.empty();
                List<WhotCard> known = discards.stream().map(WhotCard::parse).toList();
                if (known.isEmpty() || !known.getLast().equals(top) || known.size() > discardCount) known = List.of(top);
                return Optional.of(new Observation(players, hand, counts, known, discardCount, market, top, active, pending, config, tell));
            } catch (IllegalArgumentException | ClassCastException e) {
                return Optional.empty(); // Incomplete/imported snapshots retain the adapter's legal heuristic.
            }
        }
    }

    private final Limits limits;
    private final long deadline;
    private int transitions;

    private WhotMonteCarloSearch(Limits limits) {
        this.limits = limits;
        deadline = System.nanoTime() + limits.millis() * 1_000_000;
    }

    public static Decision choose(Observation observation, String player, Limits limits, Random random) {
        var search = new WhotMonteCarloSearch(limits);
        List<WhotCard> unknown = unknownCards(observation);
        if (unknown.isEmpty()) return new Decision(Optional.empty(), 0, 0);
        WhotState initial = sample(observation, player, unknown, new Random(random.nextLong()));
        List<PlayerAction> actions = actions(initial);
        if (actions.isEmpty()) return new Decision(Optional.empty(), 0, 0);
        if (actions.size() == 1) {
            PlayerAction forced = actions.getFirst();
            return new Decision(Optional.of(PlayerAction.of(player, forced.type(), forced.data())), 0, 0);
        }
        PlayerAction best = actions.stream().max(Comparator.comparingDouble(a -> policyScore(initial, a))).orElseThrow();
        double[] totals = new double[actions.size()];
        int completed = 0;
        for (int round = 0; round < limits.samples(); round++) {
            try {
                search.check();
                WhotState deal = sample(observation, player, unknown, random);
                long rolloutSeed = random.nextLong();
                double[] scores = new double[actions.size()];
                // Each candidate sees the same deal and rollout random seed. Commit only a full comparison.
                for (int i = 0; i < actions.size(); i++) {
                    WhotState state = search.play(deal, actions.get(i));
                    Random policy = new Random(rolloutSeed);
                    for (int ply = 1; ply < limits.plies() && !state.finished(); ply++) {
                        search.check();
                        List<PlayerAction> legal = actions(state);
                        if (legal.isEmpty()) break;
                        WhotState current = state;
                        PlayerAction action = policy.nextDouble() < .12 ? legal.get(policy.nextInt(legal.size()))
                                : legal.stream().max(Comparator.comparingDouble(a -> policyScore(current, a))).orElseThrow();
                        state = search.play(state, action);
                    }
                    scores[i] = evaluate(state, player);
                }
                completed++;
                int bestIndex = 0;
                for (int i = 0; i < actions.size(); i++) {
                    totals[i] += scores[i];
                    if (totals[i] + .001 * policyScore(initial, actions.get(i))
                            > totals[bestIndex] + .001 * policyScore(initial, actions.get(bestIndex))) bestIndex = i;
                }
                best = actions.get(bestIndex);
            } catch (Exhausted ignored) { break; }
            catch (RuleViolation e) {
                // A sampled branch can exhaust all drawable cards. Do not score an incomplete comparison.
                if (!"DECK_EXHAUSTED".equals(e.code())) throw e;
            }
        }
        return new Decision(Optional.of(PlayerAction.of(player, best.type(), best.data())), completed, search.transitions);
    }

    /** Removes known cards with multiplicity; the public total reveals how many decks were combined. */
    static List<WhotCard> unknownCards(Observation o) {
        List<WhotCard> single = WhotModule.singleDeck(o.config());
        int total = o.discardCount() + o.marketLeft() + o.handSizes().values().stream().mapToInt(Integer::intValue).sum();
        if (total <= 0 || total % single.size() != 0 || total > 1500) return List.of();
        List<WhotCard> unknown = new ArrayList<>();
        for (int i = 0; i < total / single.size(); i++) unknown.addAll(single);
        for (WhotCard card : o.hand()) if (!unknown.remove(card)) return List.of();
        for (WhotCard card : o.knownDiscards()) if (!unknown.remove(card)) return List.of();
        return unknown;
    }

    static WhotState sample(Observation o, String player, List<WhotCard> unknown, Random random) {
        List<WhotCard> shuffled = new ArrayList<>(unknown);
        Collections.shuffle(shuffled, random);
        var draft = new WhotState.Draft();
        if (o.tell() != null) {
            draft.teams.addAll(o.tell().teams()); draft.qualifiedTeams.addAll(o.tell().qualified());
            draft.eliminatedTeams.addAll(o.tell().eliminated()); draft.stage = o.tell().stage();
        }
        draft.config = o.config(); draft.players = new ArrayList<>(o.players());
        draft.turnIndex = o.players().indexOf(player); draft.pendingPick = o.pendingPick();
        draft.demandedShape = o.top().isWhot() ? o.activeShape() : null;
        int at = 0;
        for (String p : o.players()) {
            int size = o.handSizes().get(p);
            draft.hands.put(p, new ArrayList<>(p.equals(player) ? o.hand() : shuffled.subList(at, at + size)));
            if (!p.equals(player)) at += size;
        }
        draft.pile.addAll(o.knownDiscards().subList(0, o.knownDiscards().size() - 1));
        int missing = o.discardCount() - o.knownDiscards().size();
        draft.pile.addAll(shuffled.subList(at, at + missing)); at += missing;
        draft.pile.add(o.top());
        draft.market.addAll(shuffled.subList(at, shuffled.size()));
        return draft.build();
    }

    static List<PlayerAction> actions(WhotState state) {
        if (state.finished() || !("Turn".equals(state.phase) || "Waiting".equals(state.phase))) return List.of();
        String actor = state.currentPlayer();
        List<PlayerAction> legal = new ArrayList<>();
        for (WhotCard card : new LinkedHashSet<>(state.handOf(actor))) {
            boolean matches = state.pendingPick > 0
                    ? card.number() == 2 && state.config.pickTwo() && state.config.pickTwoStacking()
                    : card.isWhot() || card.shape() == state.activeShape() || card.number() == state.topCard().number();
            if (!matches) continue;
            if (card.isWhot()) {
                for (var shape : SHAPES) legal.add(action(actor, "PLAY", Map.of("card", card.code(), "shape", shape.name().toLowerCase(Locale.ROOT))));
            } else legal.add(action(actor, "PLAY", Map.of("card", card.code())));
        }
        if (legal.isEmpty()) legal.add(action(actor, "DRAW", Map.of()));
        return legal;
    }

    /** Rollout players use only their own sampled hand and public counts, never opponents' card identities. */
    private static double policyScore(WhotState state, PlayerAction action) {
        if (action.type().equals("DRAW")) return -100;
        List<WhotCard> hand = state.handOf(action.actor());
        WhotCard card = WhotCard.parse((String) action.data().get("card"));
        if (hand.size() == 1) return 10000;
        WhotCard.Shape shape = card.isWhot()
                ? WhotCard.Shape.valueOf(((String) action.data().get("shape")).toUpperCase(Locale.ROOT)) : card.shape();
        long continuity = hand.stream().filter(c -> c.shape() == shape || c.number() == card.number()).count() - (card.isWhot() ? 0 : 1);
        double score = continuity * 8 - (card.isWhot() ? 25 : 0);
        if (card.number() == 1 && state.config.holdOn()) score += 18;
        if (card.number() == 8 && state.config.suspension()) score += 16;
        if (card.number() == 14 && state.config.generalMarket()) score += 22;
        if (card.number() == 2 && state.config.pickTwo()) score += 20;
        if (state.config.tell()) {
            List<WhotCard> after = new ArrayList<>(hand); after.remove(card);
            score += setPotential(after, state.config);
            String next = nextActive(state, action.actor());
            if (teamOf(state, next) == teamOf(state, action.actor())) {
                if (card.number() == 2 && state.config.pickTwo()) score -= 50;
                if (card.number() == 8 && state.config.suspension()) score -= 40;
            }
        }
        return score;
    }

    private static double evaluate(WhotState state, String player) {
        if (state.config.tell()) {
            int team = teamOf(state, player);
            if (state.finished()) return state.win.winningSide().equals("team-" + team) ? 10000 : -10000;
            if (state.eliminatedTeams.contains(team)) return -10000;
            if (state.qualifiedTeams.contains(team)) return 5000;
            if ("Signals".equals(state.phase) && "final".equals(state.stage)) return 5000;
            int mine = state.teams.get(team).stream().mapToInt(p -> state.handOf(p).size()).min().orElse(0);
            int closest = state.players.stream().filter(p -> teamOf(state, p) != team && active(state, p))
                    .mapToInt(p -> state.handOf(p).size()).min().orElse(mine);
            double potential = state.teams.get(team).stream().mapToDouble(p -> setPotential(state.handOf(p), state.config)).max().orElse(0);
            return (closest - mine) * 80 - mine * 2 + potential;
        }
        if (state.finished()) return state.win.winningSide().equals(player) ? 10000 : -10000;
        int mine = state.handOf(player).size();
        int closest = state.players.stream().filter(p -> !p.equals(player)).mapToInt(p -> state.handOf(p).size()).min().orElse(mine);
        return Math.max(-1000, Math.min(1000, (closest - mine) * 80 - mine * 2 + (state.currentPlayer().equals(player) ? 5 : 0)));
    }

    private static double setPotential(List<WhotCard> hand, WhotConfig config) {
        if (hand.size() < config.tellMinCards()) return 0;
        if (WhotModule.hasSet(hand, config)) return 650;
        int match = 0;
        for (WhotCard card : hand) {
            if (!"value".equals(config.tellRule())) match = Math.max(match, (int) hand.stream().filter(c -> c.shape() == card.shape()).count());
            if (!"shape".equals(config.tellRule())) match = Math.max(match, (int) hand.stream().filter(c -> c.number() == card.number()).count());
        }
        return match >= config.tellMinCards() ? 30.0 * match / hand.size() : 0;
    }

    private static int teamOf(WhotState state, String player) {
        for (int i = 0; i < state.teams.size(); i++) if (state.teams.get(i).contains(player)) return i;
        return -1;
    }

    private static boolean active(WhotState state, String player) {
        int team = teamOf(state, player);
        return !state.qualifiedTeams.contains(team) && !state.eliminatedTeams.contains(team);
    }

    private static String nextActive(WhotState state, String actor) {
        int at = state.players.indexOf(actor);
        for (int offset = 1; offset < state.players.size(); offset++) {
            String player = state.players.get((at + offset) % state.players.size());
            if (active(state, player)) return player;
        }
        return actor;
    }

    private static List<Integer> indices(Object raw) {
        if (!(raw instanceof List<?> list)) return List.of();
        return list.stream().map(x -> ((Number) x).intValue()).toList();
    }

    private WhotState play(WhotState state, PlayerAction action) {
        check(); transitions++;
        WhotState next = (WhotState) GAME.onPlayerAction(state, action);
        var draft = new WhotState.Draft(next);
        draft.events.clear(); draft.appliedActionIds.clear(); draft.seq = 0;
        return draft.build();
    }

    private void check() {
        if (transitions >= limits.transitions() || System.nanoTime() >= deadline || Thread.currentThread().isInterrupted())
            throw new Exhausted();
    }

    private static PlayerAction action(String actor, String type, Map<String, Object> data) {
        return new PlayerAction("simulation", actor, type, data);
    }
    private static int number(Object value) { return value instanceof Number n ? n.intValue() : -1; }
    private static boolean on(Map<?, ?> rules, String key) { return Boolean.TRUE.equals(rules.get(key)); }
    private static final class Exhausted extends RuntimeException { Exhausted() { super(null, null, false, false); } }
}
