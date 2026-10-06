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
    final Map<String, String> secondNightSubmissions;
    final String nightTarget;
    final boolean nightSkipUsed;
    final Map<String, String> votes;
    final Set<String> voteLocked;
    final int votesRevealed;
    final List<String> tieCandidates;
    final int tieStage;
    final String accuser;
    final String accused;
    final boolean accusationUsed;
    final String shieldHolder;
    final boolean shieldPoisoned;
    final boolean shieldAvailable;
    /** Poisoned players and the round whose night they die in. More than one can be pending. */
    final Map<String, Integer> poisonDue;
    final int giftUses;
    final String immunityHolder;
    final boolean immunitySpent;
    /** The game's one coin has been used (or expired). It can't be awarded again. */
    final boolean immunityConsumed;
    final int eliminationIndex;
    final List<String> eliminatedLog;
    final Map<String, String> eliminationCause;
    final Map<String, Boolean> eliminationRoleShown;
    final boolean recruitDone;
    // --- twists wired after the initial audit (docs/GAME_CONFIG.md §5) ---
    final int falseRevealUses;
    final String silentWitness;
    final String blackmailer;
    final String blackmailTarget;
    final Map<String, String> confessionals;
    final Set<String> survivorsChoiceVotes;
    final String doubleAgentCandidate;
    final boolean doubleAgentRecruited;
    final Map<String, String> lastWills;
    final boolean tieDefensePending;
    /** false_reveal: Traitors have committed to hiding the next banished Faithful's role. */
    final boolean falseRevealArmed;
    /**
     * Every resolved ballot, in order — {@code {round, stage, votes}}. Kept so the
     * Results screen can release the votes a veiled endgame withheld.
     */
    final List<Map<String, Object>> ballotHistory;
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
        this.secondNightSubmissions = Collections.unmodifiableMap(new LinkedHashMap<>(d.secondNightSubmissions));
        this.nightTarget = d.nightTarget;
        this.nightSkipUsed = d.nightSkipUsed;
        this.votes = Collections.unmodifiableMap(new LinkedHashMap<>(d.votes));
        this.voteLocked = Collections.unmodifiableSet(new LinkedHashSet<>(d.voteLocked));
        this.votesRevealed = d.votesRevealed;
        this.tieCandidates = List.copyOf(d.tieCandidates);
        this.tieStage = d.tieStage;
        this.accuser = d.accuser;
        this.accused = d.accused;
        this.accusationUsed = d.accusationUsed;
        this.shieldHolder = d.shieldHolder;
        this.shieldPoisoned = d.shieldPoisoned;
        this.shieldAvailable = d.shieldAvailable;
        this.poisonDue = Collections.unmodifiableMap(new LinkedHashMap<>(d.poisonDue));
        this.giftUses = d.giftUses;
        this.immunityHolder = d.immunityHolder;
        this.immunitySpent = d.immunitySpent;
        this.immunityConsumed = d.immunityConsumed;
        this.eliminationIndex = d.eliminationIndex;
        this.eliminatedLog = List.copyOf(d.eliminatedLog);
        this.eliminationCause = Collections.unmodifiableMap(new LinkedHashMap<>(d.eliminationCause));
        this.eliminationRoleShown = Collections.unmodifiableMap(new LinkedHashMap<>(d.eliminationRoleShown));
        this.recruitDone = d.recruitDone;
        this.falseRevealUses = d.falseRevealUses;
        this.silentWitness = d.silentWitness;
        this.blackmailer = d.blackmailer;
        this.blackmailTarget = d.blackmailTarget;
        this.confessionals = Collections.unmodifiableMap(new LinkedHashMap<>(d.confessionals));
        this.survivorsChoiceVotes = Collections.unmodifiableSet(new LinkedHashSet<>(d.survivorsChoiceVotes));
        this.doubleAgentCandidate = d.doubleAgentCandidate;
        this.doubleAgentRecruited = d.doubleAgentRecruited;
        this.lastWills = Collections.unmodifiableMap(new LinkedHashMap<>(d.lastWills));
        this.tieDefensePending = d.tieDefensePending;
        this.falseRevealArmed = d.falseRevealArmed;
        this.ballotHistory = List.copyOf(d.ballotHistory);
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
        Map<String, String> secondNightSubmissions = new LinkedHashMap<>();
        String nightTarget;
        boolean nightSkipUsed;
        Map<String, String> votes = new LinkedHashMap<>();
        Set<String> voteLocked = new LinkedHashSet<>();
        int votesRevealed;
        List<String> tieCandidates = new ArrayList<>();
        int tieStage;
        String accuser;
        String accused;
        boolean accusationUsed;
        String shieldHolder;
        boolean shieldPoisoned;
        boolean shieldAvailable;
        Map<String, Integer> poisonDue = new LinkedHashMap<>();
        int giftUses;
        String immunityHolder;
        boolean immunitySpent;
        boolean immunityConsumed;
        int eliminationIndex;
        List<String> eliminatedLog = new ArrayList<>();
        Map<String, String> eliminationCause = new LinkedHashMap<>();
        Map<String, Boolean> eliminationRoleShown = new LinkedHashMap<>();
        boolean recruitDone;
        int falseRevealUses;
        String silentWitness;
        String blackmailer;
        String blackmailTarget;
        Map<String, String> confessionals = new LinkedHashMap<>();
        Set<String> survivorsChoiceVotes = new LinkedHashSet<>();
        String doubleAgentCandidate;
        boolean doubleAgentRecruited;
        Map<String, String> lastWills = new LinkedHashMap<>();
        boolean tieDefensePending;
        boolean falseRevealArmed;
        List<Map<String, Object>> ballotHistory = new ArrayList<>();
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
            this.secondNightSubmissions = new LinkedHashMap<>(s.secondNightSubmissions);
            this.nightTarget = s.nightTarget;
            this.nightSkipUsed = s.nightSkipUsed;
            this.votes = new LinkedHashMap<>(s.votes);
            this.voteLocked = new LinkedHashSet<>(s.voteLocked);
            this.votesRevealed = s.votesRevealed;
            this.tieCandidates = new ArrayList<>(s.tieCandidates);
            this.tieStage = s.tieStage;
            this.accuser = s.accuser;
            this.accused = s.accused;
            this.accusationUsed = s.accusationUsed;
            this.shieldHolder = s.shieldHolder;
            this.shieldPoisoned = s.shieldPoisoned;
            this.shieldAvailable = s.shieldAvailable;
            this.poisonDue = new LinkedHashMap<>(s.poisonDue);
            this.giftUses = s.giftUses;
            this.immunityHolder = s.immunityHolder;
            this.immunitySpent = s.immunitySpent;
            this.immunityConsumed = s.immunityConsumed;
            this.eliminationIndex = s.eliminationIndex;
            this.eliminatedLog = new ArrayList<>(s.eliminatedLog);
            this.eliminationCause = new LinkedHashMap<>(s.eliminationCause);
            this.eliminationRoleShown = new LinkedHashMap<>(s.eliminationRoleShown);
            this.recruitDone = s.recruitDone;
            this.falseRevealUses = s.falseRevealUses;
            this.silentWitness = s.silentWitness;
            this.blackmailer = s.blackmailer;
            this.blackmailTarget = s.blackmailTarget;
            this.confessionals = new LinkedHashMap<>(s.confessionals);
            this.survivorsChoiceVotes = new LinkedHashSet<>(s.survivorsChoiceVotes);
            this.doubleAgentCandidate = s.doubleAgentCandidate;
            this.doubleAgentRecruited = s.doubleAgentRecruited;
            this.lastWills = new LinkedHashMap<>(s.lastWills);
            this.tieDefensePending = s.tieDefensePending;
            this.falseRevealArmed = s.falseRevealArmed;
            this.ballotHistory = new ArrayList<>(s.ballotHistory);
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
