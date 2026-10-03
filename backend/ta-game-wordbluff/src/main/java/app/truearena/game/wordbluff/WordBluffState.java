package app.truearena.game.wordbluff;

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
 * Immutable snapshot of a Word Bluff game. Built only via {@link Draft}, same
 * convention as {@code TruearenaState} in the flagship module.
 */
public final class WordBluffState implements GameState {

    static final String TEAM_A = "A";
    static final String TEAM_B = "B";

    /**
     * One word played during a turn. Marks are provisional until the turn's
     * review round is accepted by both teams — that's the whole point of
     * collecting them instead of scoring each word on the spot.
     */
    record Attempt(String word, String category, boolean correct, boolean skipped, String markedBy) {
        Attempt flipped(String byUserId) {
            // A skipped word can be corrected into a scoring one during
            // review (and back) — "skip" is just a mark the describer made.
            return new Attempt(word, category, !correct, false, byUserId);
        }
    }

    final String phase;
    final int round;
    final List<String> teamA;
    final List<String> teamB;
    final int teamAScore;
    final int teamBScore;
    final String turnTeam;
    final int describerIndexA;
    final int describerIndexB;
    final Category currentCategory; // null = no pending spin this word
    final boolean clockStarted;
    final String currentWord; // null = not yet revealed (or already resolved)
    final Set<String> usedWords;
    /** This turn's words so far — cleared when the next turn starts. */
    final List<Attempt> turnAttempts;
    /** Which teams have signed off on the review ("A"/"B"); both ⇒ commit. */
    final Set<String> reviewAccepted;
    final WordBluffConfig config;
    final long seed;
    final long drawCounter;
    final Set<String> appliedActionIds;
    final List<GameEvent> events;
    final long seq;
    final WinResult win;

    private WordBluffState(Draft d) {
        this.phase = d.phase;
        this.round = d.round;
        this.teamA = List.copyOf(d.teamA);
        this.teamB = List.copyOf(d.teamB);
        this.teamAScore = d.teamAScore;
        this.teamBScore = d.teamBScore;
        this.turnTeam = d.turnTeam;
        this.describerIndexA = d.describerIndexA;
        this.describerIndexB = d.describerIndexB;
        this.currentCategory = d.currentCategory;
        this.clockStarted = d.clockStarted;
        this.currentWord = d.currentWord;
        this.usedWords = Set.copyOf(d.usedWords);
        this.turnAttempts = List.copyOf(d.turnAttempts);
        this.reviewAccepted = Set.copyOf(d.reviewAccepted);
        this.config = d.config;
        this.seed = d.seed;
        this.drawCounter = d.drawCounter;
        this.appliedActionIds = Set.copyOf(d.appliedActionIds);
        this.events = List.copyOf(d.events);
        this.seq = d.seq;
        this.win = d.win;
    }

    @Override public String phase() { return phase; }
    @Override public int round() { return round; }
    @Override public boolean finished() { return "Results".equals(phase); }
    @Override public List<GameEvent> events() { return events; }

    List<String> teamOf(String side) {
        return TEAM_A.equals(side) ? teamA : teamB;
    }

    int scoreOf(String side) {
        return TEAM_A.equals(side) ? teamAScore : teamBScore;
    }

    String currentDescriber() {
        List<String> team = teamOf(turnTeam);
        int idx = TEAM_A.equals(turnTeam) ? describerIndexA : describerIndexB;
        return team.get(idx % team.size());
    }

    String otherTeam(String side) {
        return TEAM_A.equals(side) ? TEAM_B : TEAM_A;
    }

    /** "A"/"B" for a player, or null if they aren't on either team (a spectator). */
    String teamOfPlayer(String userId) {
        if (teamA.contains(userId)) return TEAM_A;
        if (teamB.contains(userId)) return TEAM_B;
        return null;
    }

    /** Mutable builder — the only way to derive a new {@link WordBluffState}. */
    static final class Draft {
        String phase;
        int round;
        List<String> teamA = new ArrayList<>();
        List<String> teamB = new ArrayList<>();
        int teamAScore;
        int teamBScore;
        String turnTeam;
        int describerIndexA;
        int describerIndexB;
        Category currentCategory;
        boolean clockStarted;
        String currentWord;
        Set<String> usedWords = new LinkedHashSet<>();
        List<Attempt> turnAttempts = new ArrayList<>();
        Set<String> reviewAccepted = new LinkedHashSet<>();
        WordBluffConfig config;
        long seed;
        long drawCounter;
        Set<String> appliedActionIds = new LinkedHashSet<>();
        List<GameEvent> events = new ArrayList<>();
        long seq;
        WinResult win;

        Draft() {
        }

        Draft(WordBluffState s) {
            this.phase = s.phase;
            this.round = s.round;
            this.teamA = new ArrayList<>(s.teamA);
            this.teamB = new ArrayList<>(s.teamB);
            this.teamAScore = s.teamAScore;
            this.teamBScore = s.teamBScore;
            this.turnTeam = s.turnTeam;
            this.describerIndexA = s.describerIndexA;
            this.describerIndexB = s.describerIndexB;
            this.currentCategory = s.currentCategory;
            this.clockStarted = s.clockStarted;
            this.currentWord = s.currentWord;
            this.usedWords = new LinkedHashSet<>(s.usedWords);
            this.turnAttempts = new ArrayList<>(s.turnAttempts);
            this.reviewAccepted = new LinkedHashSet<>(s.reviewAccepted);
            this.config = s.config;
            this.seed = s.seed;
            this.drawCounter = s.drawCounter;
            this.appliedActionIds = new LinkedHashSet<>(s.appliedActionIds);
            this.events = new ArrayList<>(s.events);
            this.seq = s.seq;
            this.win = s.win;
        }

        WordBluffState build() {
            return new WordBluffState(this);
        }

        void emit(String type, Map<String, Object> payload) {
            events.add(GameEvent.pub(++seq, type, payload));
        }

        void emitToPlayer(String type, Map<String, Object> payload, String playerId) {
            events.add(GameEvent.toPlayer(++seq, type, payload, playerId));
        }
    }
}
