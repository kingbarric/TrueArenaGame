package app.truearena.game.ludo;

import app.truearena.engine.*;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.SplittableRandom;

/** Two independent dice per roll; each die moves one chosen token. */
public final class LudoModule implements GameModule {
    private static final Set<Integer> SAFE = Set.of(0, 8, 13, 21, 26, 34, 39, 47);
    // Seat order is red, green, yellow, blue. Two players occupy opposite corners.
    private static final List<Integer> SEATS_TWO = List.of(0, 2);
    private static final List<Integer> SEATS_THREE = List.of(0, 1, 2);
    private static final List<Integer> SEATS_FOUR = List.of(0, 1, 2, 3);

    @Override public String gameType() { return "ludo"; }
    @Override public boolean hasPrivatePlayerState() { return true; }

    @Override public List<Phase> definePhases(GameSettings settings) {
        return List.of(new Phase("Turn", ((LudoConfig) settings).turnSeconds()), Phase.untimed("Results"));
    }

    @Override public GameState initialState(List<String> players, GameSettings settings, RandomSource rng) {
        if (players.size() < 2 || players.size() > 4 || Set.copyOf(players).size() != players.size()) {
            throw new RuleViolation("BAD_PLAYER_COUNT", "Ludo needs 2 to 4 distinct players");
        }
        int pieceCount = players.size() == 2 ? ((LudoConfig) settings).twoPlayerPieces() : 4;
        Map<String, List<Integer>> pieces = new LinkedHashMap<>();
        players.forEach(p -> pieces.put(p, java.util.Collections.nCopies(pieceCount, -1)));
        GameEvent start = GameEvent.pub(1, "GAME_STARTED", Map.of("players", List.copyOf(players), "turnPlayer", players.get(0)));
        return new LudoState("Turn", 1, players, pieces, 0, List.of(), 0, 0, rng.seed(), null,
                Set.of(), Set.of(), List.of(start), (LudoConfig) settings);
    }

    @Override public GameState onPlayerAction(GameState state, PlayerAction action) {
        LudoState s = (LudoState) state;
        if (s.finished() || s.actionIds().contains(action.actionId())) return s;
        if (!s.players().contains(action.actor()) || s.eliminated().contains(action.actor())) {
            throw new RuleViolation("NOT_A_PLAYER", "you are not in this game");
        }
        if (!"FORFEIT".equals(action.type()) && !s.turnPlayer().equals(action.actor())) {
            throw new RuleViolation("NOT_YOUR_TURN", "wait for your turn");
        }
        return switch (action.type()) {
            case "ROLL" -> roll(s, action);
            case "MOVE" -> move(s, action);
            case "FORFEIT" -> forfeit(s, action);
            default -> throw new RuleViolation("UNKNOWN_ACTION", "unknown Ludo action");
        };
    }

    private LudoState roll(LudoState s, PlayerAction action) {
        if (!s.dice().isEmpty()) throw new RuleViolation("MOVE_FIRST", "use your remaining dice first");
        // The seed is stored with the session, while the current roll counter is part of state.
        // Clients cannot choose a value. Replaying a session yields the same dice.
        SplittableRandom random = new SplittableRandom(s.seed() ^ (0x9E3779B97F4A7C15L * (s.rollCount() + 1L)));
        List<Integer> rolled = List.of(random.nextInt(1, 7), random.nextInt(1, 7));
        // Keep both dice: a six can release a token and make the other die playable.
        boolean anyMove = rolled.stream().anyMatch(die -> hasMove(s, s.turnPlayer(), die));
        int bonus = rolled.get(0) == 6 && rolled.get(1) == 6 ? 1 : 0;
        LudoState next = changed(s, action.actionId(), s.pieces(), s.turnIndex(), anyMove ? rolled : List.of(),
                s.rollCount() + 1, bonus, null, "DICE_ROLLED", Map.of("player", action.actor(), "dice", rolled));
        return anyMove ? next : finishDice(next);
    }

    private LudoState move(LudoState s, PlayerAction action) {
        if (s.dice().isEmpty()) throw new RuleViolation("ROLL_FIRST", "roll the dice first");
        int die = number(action.data().get("die"));
        int token = number(action.data().get("token"));
        if (!s.dice().contains(die) || token < 0 || token >= s.pieces().get(action.actor()).size()
                || !legal(s, action.actor(), token, die)) {
            throw new RuleViolation("ILLEGAL_MOVE", "that token cannot use this die");
        }
        Map<String, List<Integer>> pieces = new LinkedHashMap<>(s.pieces());
        List<Integer> mine = new ArrayList<>(pieces.get(action.actor()));
        int from = mine.get(token);
        int to = from == -1 ? 0 : from + die;
        mine.set(token, to);
        pieces.put(action.actor(), List.copyOf(mine));
        List<String> captured = new ArrayList<>();
        int landing = to <= 50 ? square(s, action.actor(), to) : -1;
        if (landing >= 0 && !SAFE.contains(landing)) {
            for (String opponent : s.players()) {
                if (opponent.equals(action.actor())) continue;
                List<Integer> other = new ArrayList<>(pieces.get(opponent));
                for (int i = 0; i < other.size(); i++) {
                    int pos = other.get(i);
                    if (pos >= 0 && pos <= 50 && square(s, opponent, pos) == landing) {
                        other.set(i, -1);
                        captured.add(opponent + ":" + i);
                    }
                }
                pieces.put(opponent, List.copyOf(other));
            }
        }
        List<Integer> remaining = new ArrayList<>(s.dice());
        remaining.remove(Integer.valueOf(die));
        remaining.removeIf(value -> !hasMoveWith(pieces, s, action.actor(), value));
        String winner = mine.stream().allMatch(p -> p == 56) ? action.actor() : null;
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("player", action.actor()); event.put("token", token); event.put("die", die);
        event.put("from", from); event.put("to", to); event.put("captured", captured);
        LudoState next = changed(s, action.actionId(), pieces, s.turnIndex(), remaining,
                s.rollCount(), s.bonusRolls(), winner, "PIECE_MOVED", event);
        return winner != null ? next : remaining.isEmpty() ? finishDice(next) : next;
    }

    private LudoState finishDice(LudoState s) {
        if (s.bonusRolls() > 0) {
            return changed(s, null, s.pieces(), s.turnIndex(), List.of(), s.rollCount(),
                    s.bonusRolls(), null, "BONUS_ROLL", Map.of("player", s.turnPlayer()));
        }
        int next = nextActive(s, s.turnIndex(), s.eliminated());
        return changed(s, null, s.pieces(), next, List.of(), s.rollCount(), 0,
                null, "TURN_STARTED", Map.of("player", s.players().get(next)));
    }

    private LudoState forfeit(LudoState s, PlayerAction action) {
        Set<String> eliminated = new HashSet<>(s.eliminated());
        eliminated.add(action.actor());
        boolean active = s.turnPlayer().equals(action.actor());
        int next = active ? nextActive(s, s.turnIndex(), eliminated) : s.turnIndex();
        String winner = s.players().size() - eliminated.size() == 1 ? s.players().get(next) : null;
        LudoState nextState = changed(s, action.actionId(), s.pieces(), next,
                active ? List.of() : s.dice(), s.rollCount(),
                active ? 0 : s.bonusRolls(), winner, "PLAYER_FORFEITED",
                Map.of("player", action.actor(), "nextPlayer", s.players().get(next)));
        return new LudoState(nextState.phase(), nextState.round() + (active ? 1 : 0), nextState.players(), nextState.pieces(),
                nextState.turnIndex(), nextState.dice(), nextState.rollCount(), nextState.bonusRolls(),
                nextState.seed(), nextState.winner(), eliminated, nextState.actionIds(), nextState.events(), nextState.config());
    }

    private int nextActive(LudoState s, int from, Set<String> eliminated) {
        int next = from;
        do { next = (next + 1) % s.players().size(); }
        while (eliminated.contains(s.players().get(next)));
        return next;
    }

    private boolean hasMove(LudoState s, String player, int die) {
        return hasMoveWith(s.pieces(), s, player, die);
    }

    private boolean hasMoveWith(Map<String, List<Integer>> pieces, LudoState s, String player, int die) {
        for (int token = 0; token < pieces.get(player).size(); token++)
            if (legal(pieces, s, player, token, die)) return true;
        return false;
    }

    private boolean legal(LudoState s, String player, int token, int die) {
        return legal(s.pieces(), s, player, token, die);
    }

    private boolean legal(Map<String, List<Integer>> pieces, LudoState s, String player, int token, int die) {
        if (die < 1 || die > 6) return false;
        int pos = pieces.get(player).get(token);
        if (pos == 56 || (pos == -1 && die != 6)) return false;
        int to = pos == -1 ? 0 : pos + die;
        if (to > 56) return false;
        if (to > 50) return true;
        int landing = square(s, player, to);
        if (SAFE.contains(landing)) return true;
        for (String opponent : s.players()) {
            if (opponent.equals(player)) continue;
            int count = 0;
            for (int other : pieces.get(opponent)) {
                if (other >= 0 && other <= 50 && square(s, opponent, other) == landing) count++;
            }
            if (count >= 2) return false;
        }
        return true;
    }

    private int square(LudoState s, String player, int progress) {
        List<Integer> seats = switch (s.players().size()) {
            case 2 -> SEATS_TWO;
            case 3 -> SEATS_THREE;
            default -> SEATS_FOUR;
        };
        return (seats.get(s.players().indexOf(player)) * 13 + progress) % 52;
    }

    private static int number(Object raw) { return raw instanceof Number n ? n.intValue() : -1; }

    private LudoState changed(LudoState s, String actionId, Map<String, List<Integer>> pieces,
                              int turnIndex, List<Integer> dice, int rolls, int bonus, String winner,
                              String eventType, Map<String, Object> payload) {
        List<GameEvent> events = new ArrayList<>(s.events());
        events.add(GameEvent.pub(events.size() + 1L, eventType, payload));
        Set<String> ids = new HashSet<>(s.actionIds());
        if (actionId != null) ids.add(actionId);
        int round = s.round() + (Set.of("TURN_STARTED", "BONUS_ROLL", "TURN_TIMED_OUT").contains(eventType) ? 1 : 0);
        return new LudoState(winner == null ? "Turn" : "Results", round,
                s.players(), pieces, turnIndex, dice, rolls, bonus, s.seed(), winner,
                s.eliminated(), ids, events, s.config());
    }

    @Override public GameState onPhaseElapsed(GameState state, String endedPhase) {
        LudoState s = (LudoState) state;
        if (s.finished() || !"Turn".equals(endedPhase)) return s;
        int next = nextActive(s, s.turnIndex(), s.eliminated());
        return changed(s, null, s.pieces(), next, List.of(), s.rollCount(), 0,
                null, "TURN_TIMED_OUT", Map.of("player", s.turnPlayer(), "nextPlayer", s.players().get(next)));
    }

    @Override public Optional<WinResult> checkWinCondition(GameState state) {
        LudoState s = (LudoState) state;
        return s.finished() ? Optional.of(s.winResult()) : Optional.empty();
    }

    @Override public PlayerVisibleState visibleStateFor(GameState state, String playerId) {
        return new PlayerVisibleState(view((LudoState) state));
    }

    @Override public PublicBroadcastState broadcastState(GameState state) {
        return new PublicBroadcastState(view((LudoState) state));
    }

    private Map<String, Object> view(LudoState s) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("phase", s.phase()); data.put("round", s.round());
        data.put("players", s.players()); data.put("pieces", s.pieces());
        data.put("turnPlayer", s.turnPlayer()); data.put("dice", s.dice());
        List<Integer> rolledDice = List.of();
        if (!s.finished()) {
            for (int i = s.events().size() - 1; i >= 0; i--) {
                GameEvent event = s.events().get(i);
                if (Set.of("TURN_STARTED", "TURN_TIMED_OUT", "BONUS_ROLL").contains(event.type())) break;
                if ("DICE_ROLLED".equals(event.type())) {
                    if (s.turnPlayer().equals(event.payload().get("player"))) {
                        Object values = event.payload().get("dice");
                        if (values instanceof List<?> list) {
                            rolledDice = list.stream().filter(Number.class::isInstance)
                                    .map(Number.class::cast).map(Number::intValue).toList();
                        }
                    }
                    break;
                }
            }
        }
        data.put("rolledDice", rolledDice);
        if (!rolledDice.isEmpty()) data.put("rollPlayer", s.turnPlayer());
        List<Map<String, Integer>> legalMoves = new ArrayList<>();
        data.put("pieceCount", s.pieces().get(s.players().getFirst()).size());
        for (int die : s.dice()) {
            for (int token = 0; token < s.pieces().get(s.turnPlayer()).size(); token++) {
                if (legal(s, s.turnPlayer(), token, die)) legalMoves.add(Map.of("die", die, "token", token));
            }
        }
        data.put("legalMoves", legalMoves);
        data.put("rollCount", s.rollCount()); data.put("bonusRolls", s.bonusRolls());
        data.put("eliminated", s.eliminated());
        data.put("seats", switch (s.players().size()) { case 2 -> SEATS_TWO; case 3 -> SEATS_THREE; default -> SEATS_FOUR; });
        if (s.winner() != null) data.put("winner", s.winner());
        return data;
    }

    @Override public List<GameEvent> drainEvents(GameState prev, GameState next) {
        List<GameEvent> a = ((LudoState) prev).events();
        List<GameEvent> b = ((LudoState) next).events();
        return b.subList(a.size(), b.size());
    }
}
