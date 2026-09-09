package app.truearena.game.truearena;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.WinResult;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Immutable snapshot of a Traitors-and-Faithful game. Built only via {@link Draft} so the
 * reducer reads as {@code new Draft(prev)....build()}.
 */
public final class TruearenaState implements GameState {

    static final String TRAITOR = "traitor";
    static final String FAITHFUL = "faithful";
    static final String RECRUITED = "recruited_traitor";

    final String phase;
    final int round;
    final List<String> players;
    final Map<String, String> roles;
    final Set<String> alive;
    final Set<String> originalTraitors;
    final Map<String, String> nightSubmissions;
    final String nightTarget;
    final boolean nightSkipUsed;
    final Map<String, String> votes;
    final Set<String> voteLocked;
    final int votesRevealed;
    final int eliminationIndex;
    final List<String> eliminatedLog;
    final Map<String, String> eliminationCause;
    final Map<String, Boolean> eliminationRoleShown;
    final boolean recruitDone;
    final GameConfig config;
    final long seed;
    final Set<String> appliedActionIds;
    final List<GameEvent> events;
    final long seq;
    final WinResult win;

    private TruearenaState(Draft d) {
        this.phase = d.phase;
        this.round = d.round;
        this.players = List.copyOf(d.players);
        this.roles = Collections.unmodifiableMap(new LinkedHashMap<>(d.roles));
        this.alive = Collections.unmodifiableSet(new LinkedHashSet<>(d.alive));
        this.originalTraitors = Set.copyOf(d.originalTraitors);
        this.nightSubmissions = Collections.unmodifiableMap(new LinkedHashMap<>(d.nightSubmissions));
        this.nightTarget = d.nightTarget;
        this.nightSkipUsed = d.nightSkipUsed;
        this.votes = Collections.unmodifiableMap(new LinkedHashMap<>(d.votes));
        this.voteLocked = Collections.unmodifiableSet(new LinkedHashSet<>(d.voteLocked));
        this.votesRevealed = d.votesRevealed;
        this.eliminationIndex = d.eliminationIndex;
        this.eliminatedLog = List.copyOf(d.eliminatedLog);
        this.eliminationCause = Collections.unmodifiableMap(new LinkedHashMap<>(d.eliminationCause));
        this.eliminationRoleShown = Collections.unmodifiableMap(new LinkedHashMap<>(d.eliminationRoleShown));
        this.recruitDone = d.recruitDone;
        this.config = d.config;
        this.seed = d.seed;
        this.appliedActionIds = Set.copyOf(d.appliedActionIds);
        this.events = List.copyOf(d.events);
        this.seq = d.seq;
        this.win = d.win;
    }

    @Override public String phase() { return phase; }
    @Override public int round() { return round; }
    @Override public boolean finished() { return win != null; }
    @Override public List<GameEvent> events() { return events; }

    boolean isTraitor(String id) {
        String r = roles.get(id);
        return TRAITOR.equals(r) || RECRUITED.equals(r);
    }

    List<String> aliveTraitors() {
        return alive.stream().filter(this::isTraitor).toList();
    }

    List<String> aliveFaithful() {
        return alive.stream().filter(id -> !isTraitor(id)).toList();
    }

    static TruearenaState initial(List<String> playerIds, GameConfig config, long seed) {
        Draft d = new Draft();
        d.phase = "RoleReveal";
        d.round = 1;
        d.players = new ArrayList<>(playerIds);
        d.config = config;
        d.seed = seed;
        return d.build();
    }

    /** Mutable working copy. Every reducer transition creates one, mutates, and calls {@link #build()}. */
    static final class Draft {
        String phase = "Lobby";
        int round = 1;
        List<String> players = new ArrayList<>();
        Map<String, String> roles = new LinkedHashMap<>();
        Set<String> alive = new LinkedHashSet<>();
        Set<String> originalTraitors = new LinkedHashSet<>();
        Map<String, String> nightSubmissions = new LinkedHashMap<>();
        String nightTarget;
        boolean nightSkipUsed;
        Map<String, String> votes = new LinkedHashMap<>();
        Set<String> voteLocked = new LinkedHashSet<>();
        int votesRevealed;
        int eliminationIndex;
        List<String> eliminatedLog = new ArrayList<>();
        Map<String, String> eliminationCause = new LinkedHashMap<>();
        Map<String, Boolean> eliminationRoleShown = new LinkedHashMap<>();
        boolean recruitDone;
        GameConfig config;
        long seed;
        Set<String> appliedActionIds = new LinkedHashSet<>();
        List<GameEvent> events = new ArrayList<>();
        long seq;
        WinResult win;

        Draft() {
        }

        Draft(TruearenaState s) {
            this.phase = s.phase;
            this.round = s.round;
            this.players = new ArrayList<>(s.players);
            this.roles = new LinkedHashMap<>(s.roles);
            this.alive = new LinkedHashSet<>(s.alive);
            this.originalTraitors = new LinkedHashSet<>(s.originalTraitors);
            this.nightSubmissions = new LinkedHashMap<>(s.nightSubmissions);
            this.nightTarget = s.nightTarget;
            this.nightSkipUsed = s.nightSkipUsed;
            this.votes = new LinkedHashMap<>(s.votes);
            this.voteLocked = new LinkedHashSet<>(s.voteLocked);
            this.votesRevealed = s.votesRevealed;
            this.eliminationIndex = s.eliminationIndex;
            this.eliminatedLog = new ArrayList<>(s.eliminatedLog);
            this.eliminationCause = new LinkedHashMap<>(s.eliminationCause);
            this.eliminationRoleShown = new LinkedHashMap<>(s.eliminationRoleShown);
            this.recruitDone = s.recruitDone;
            this.config = s.config;
            this.seed = s.seed;
            this.appliedActionIds = new LinkedHashSet<>(s.appliedActionIds);
            this.events = new ArrayList<>(s.events);
            this.seq = s.seq;
            this.win = s.win;
        }

        void emit(String type, Map<String, Object> payload) {
            events.add(GameEvent.pub(++seq, type, payload));
        }

        void emitToPlayer(String type, Map<String, Object> payload, String playerId) {
            events.add(GameEvent.toPlayer(++seq, type, payload, playerId));
        }

        void emitToRole(String type, Map<String, Object> payload, String role) {
            events.add(GameEvent.toRole(++seq, type, payload, role));
        }

        TruearenaState build() {
            return new TruearenaState(this);
        }
    }
}
