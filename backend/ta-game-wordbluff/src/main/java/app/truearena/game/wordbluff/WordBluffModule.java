package app.truearena.game.wordbluff;

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

/**
 * Word Bluff — a Catch Phrase / Heads Up-style party game: teams take turns
 * spinning a 20-category wheel, revealing a word, and racing a shared clock
 * to guess it before time or skips run out. See docs/DEV_REFERENCE.md for the
 * full rule writeup. A real {@link GameModule}, running through the same
 * {@code GameOrchestrator}/WS transport as TrueArena — {@link WordBluffConfig}
 * implements {@link GameSettings} the same way TrueArena's {@code GameConfig} does.
 */
public final class WordBluffModule implements GameModule {

    public static final String GAME_TYPE = "wordbluff";

    @Override
    public String gameType() {
        return GAME_TYPE;
    }

    @Override
    public List<Phase> definePhases(GameSettings settings) {
        WordBluffConfig config = (WordBluffConfig) settings;
        return List.of(
                new Phase("Turn", config.turnSeconds()),
                // Untimed on purpose: the review waits for both teams to
                // sign off rather than running a clock over a disagreement.
                Phase.untimed("Review"),
                new Phase("Summary", 6),
                Phase.untimed("Results")
        );
    }

    // ---------------------------------------------------------------- setup

    @Override
    public GameState initialState(List<String> playerIds, GameSettings settings, RandomSource rng) {
        WordBluffConfig config = (WordBluffConfig) settings;
        if (playerIds.size() < 4) {
            throw new RuleViolation("NOT_ENOUGH_PLAYERS", "Word Bluff needs at least 4 players (2 per team)");
        }
        List<String> shuffled = new ArrayList<>(playerIds);
        rng.shuffle(shuffled);

        WordBluffState.Draft d = new WordBluffState.Draft();
        d.config = config;
        d.seed = rng.seed();
        for (int i = 0; i < shuffled.size(); i++) {
            (i % 2 == 0 ? d.teamA : d.teamB).add(shuffled.get(i));
        }
        d.round = 1;
        d.turnTeam = WordBluffState.TEAM_A;
        d.phase = "Turn";

        d.emit("GAME_STARTED", Map.of(
                "teamA", List.copyOf(d.teamA),
                "teamB", List.copyOf(d.teamB),
                "targetScore", config.targetScore(),
                "turnSeconds", config.turnSeconds(), "textMode", config.textMode()));
        startTurn(d);
        return d.build();
    }

    // ---------------------------------------------------------------- actions

    @Override
    public GameState onPlayerAction(GameState state, PlayerAction action) {
        WordBluffState s = (WordBluffState) state;
        if (s.finished() || s.appliedActionIds.contains(action.actionId())) {
            return s;
        }
        WordBluffState.Draft d = new WordBluffState.Draft(s);
        d.appliedActionIds.add(action.actionId());

        switch (action.type()) {
            case "SPIN" -> spin(d, s, action);
            case "START_TURN_CLOCK" -> startTurnClock(d, s, action);
            case "REVEAL" -> reveal(d, s, action);
            case "MARK_CORRECT", "MARK" -> mark(d, s, action);
            case "SKIP" -> skip(d, s, action);
            case "TEXT_CLUE" -> textClue(d, s, action);
            case "TEXT_GUESS" -> textGuess(d, s, action);
            case "TEXT_SKIP" -> {
                requireTextTurn(d, action);
                require(d.turnTeam.equals(s.teamOfPlayer(action.actor())), "NOT_YOUR_TURN", "only the describing team skips");
                record(d, false, true, action.actor(), s.currentDescriber());
            }
            case "REVIEW_TOGGLE" -> reviewToggle(d, s, action);
            case "REVIEW_ACCEPT" -> reviewAccept(d, s, action);
            case "FORFEIT" -> forfeit(d, s, action);
            case "ADVANCE_PHASE" -> advance(d, d.phase);
            default -> throw new RuleViolation("UNKNOWN_ACTION", "no handler for " + action.type());
        }
        return d.build();
    }

    @Override
    public GameState onPhaseElapsed(GameState state, String endedPhase) {
        WordBluffState s = (WordBluffState) state;
        if (s.finished()) {
            return s;
        }
        WordBluffState.Draft d = new WordBluffState.Draft(s);
        advance(d, endedPhase);
        return d.build();
    }

    private void spin(WordBluffState.Draft d, WordBluffState s, PlayerAction a) {
        require(d.phase.equals("Turn"), "WRONG_PHASE", "spinning is Turn-only");
        require(a.actor().equals(s.currentDescriber()), "NOT_YOUR_TURN", "only the describer spins");
        require(d.currentCategory == null, "ALREADY_SPUN", "resolve the current word before spinning again");

        RandomSource rng = drawRng(d);
        Category landed = Category.ALL.get(rng.nextInt(Category.ALL.size()));
        d.currentCategory = landed;
        d.emit("CATEGORY_LANDED", Map.of("category", landed.slug(), "categoryName", landed.displayName()));
        // The wheel picks the category for the whole turn, not for one word,
        // so the first word follows immediately rather than waiting on a
        // separate tap — the describer is racing a clock.
        revealNextWord(d, a.actor());
    }

    private void startTurnClock(WordBluffState.Draft d, WordBluffState s, PlayerAction a) {
        require(d.phase.equals("Turn") && d.currentCategory != null, "WRONG_PHASE", "spin first");
        require(a.actor().equals(s.currentDescriber()), "NOT_YOUR_TURN", "only the describer starts the clock");
        require(!d.clockStarted, "ALREADY_STARTED", "the turn clock is already running");
        d.clockStarted = true;
        d.emit("TURN_CLOCK_STARTED", Map.of("seconds", d.config.turnSeconds()));
    }

    /**
     * Puts the next word in front of the describer and the team marking
     * them — and nobody else.
     *
     * <p>The opposing team calls each attempt right or wrong, which they
     * can't do without knowing the word; they were marking blind. The
     * describer's own teammates must still not see it, because guessing it
     * is the whole of their job.
     */
    private void revealNextWord(WordBluffState.Draft d, String describer) {
        if (d.currentCategory == null) {
            return;
        }
        String word = pickUnusedWord(d, d.currentCategory);
        d.currentWord = word;
        Map<String, Object> payload = Map.of("word", word, "category", d.currentCategory.slug(),
                "wordIndex", d.usedWords.size());

        d.emitToPlayer("WORD_REVEALED", payload, describer);
        for (String marker : d.teamA.contains(describer) ? d.teamB : d.teamA) {
            d.emitToPlayer("WORD_REVEALED", payload, marker);
        }
        // The describer's own teammates never see the word — guessing happens
        // by voice, not through the app — but their screen still needs to know
        // a word is live, or it's stuck showing "X is about to describe…" for
        // the rest of the turn. Carries nothing sensitive, so it's fine as a
        // public broadcast rather than one more per-player emit.
        d.emit("WORD_ACTIVE", Map.of());
    }

    private void reveal(WordBluffState.Draft d, WordBluffState s, PlayerAction a) {
        require(d.phase.equals("Turn"), "WRONG_PHASE", "revealing is Turn-only");
        require(a.actor().equals(s.currentDescriber()), "NOT_YOUR_TURN", "only the describer reveals");
        require(d.currentCategory != null, "NO_PENDING_SPIN", "spin first");
        if (d.currentWord != null) {
            // Spinning now hands over the first word itself, and resolving
            // one puts the next up — so an explicit reveal has nothing left
            // to do. Kept as a no-op rather than an error because older
            // clients and the bot adapter still send it, and failing their
            // turn over a redundant action would be the wrong trade.
            return;
        }
        revealNextWord(d, a.actor());
    }

    private String pickUnusedWord(WordBluffState.Draft d, Category category) {
        List<String> pool = WordBank.wordsFor(category);
        List<String> unused = pool.stream().filter(w -> !d.usedWords.contains(w)).toList();
        if (unused.isEmpty()) {
            // this category's pool is exhausted this game — fall back to the
            // full cross-category pool rather than force a repeat.
            unused = WordBank.wordsFor(Category.MIXED).stream().filter(w -> !d.usedWords.contains(w)).toList();
        }
        if (unused.isEmpty()) {
            throw new RuleViolation("WORD_POOL_EXHAUSTED", "every word in the bank has been used this game");
        }
        RandomSource rng = drawRng(d);
        return unused.get(rng.nextInt(unused.size()));
    }

    /**
     * The *opponent* calls it, not the describing team — a describer marking
     * their own partner correct is the one thing that can't be trusted in a
     * spoken party game. Any player on the other team can press; the first
     * press lands, and a bad call is fixable in the review round.
     */
    private void mark(WordBluffState.Draft d, WordBluffState s, PlayerAction a) {
        require(d.phase.equals("Turn"), "WRONG_PHASE", "marking is Turn-only");
        require(d.currentWord != null, "NO_ACTIVE_WORD", "nothing to mark yet");
        if (a.data().get("word") instanceof String expectedWord) {
            require(d.currentWord.equals(expectedWord), "STALE_WORD", "that word has already moved on");
        }
        String actorTeam = s.teamOfPlayer(a.actor());
        require(actorTeam != null, "NOT_A_PLAYER", "only players can mark");
        require(!actorTeam.equals(d.turnTeam), "NOT_YOUR_CALL", "only the opposing team marks this word");

        boolean correct = Boolean.TRUE.equals(a.data().get("correct"));
        record(d, correct, false, a.actor(), s.currentDescriber());
    }

    private void requireTextTurn(WordBluffState.Draft d, PlayerAction a) {
        require(d.config.textMode(), "VOICE_GAME", "this game uses voice clues");
        require("Turn".equals(d.phase) && d.clockStarted, "WRONG_PHASE", "start the turn clock first");
        require(d.currentWord != null, "NO_ACTIVE_WORD", "there is no word to describe");
        require(a.data().get("wordIndex") instanceof Number n && n.intValue() == d.usedWords.size(),
                "STALE_WORD", "that word has already moved on");
    }

    private void textClue(WordBluffState.Draft d, WordBluffState s, PlayerAction a) {
        requireTextTurn(d, a);
        require(a.actor().equals(s.currentDescriber()), "NOT_YOUR_TURN", "only the describer gives clues");
        String text = String.valueOf(a.data().getOrDefault("text", "")).strip();
        require(!text.isBlank() && text.length() <= 240, "BAD_CLUE", "use a clue of 1–240 characters");
        require(!normalizeText(text).contains(normalizeText(d.currentWord)), "WORD_IN_CLUE", "describe without saying the word");
        d.emit("TEXT_CLUE", Map.of("from", a.actor(), "text", text, "wordIndex", d.usedWords.size()));
    }

    private void textGuess(WordBluffState.Draft d, WordBluffState s, PlayerAction a) {
        requireTextTurn(d, a);
        require(d.turnTeam.equals(s.teamOfPlayer(a.actor())) && !a.actor().equals(s.currentDescriber()),
                "NOT_A_GUESSER", "only the describer's teammates guess");
        String text = String.valueOf(a.data().getOrDefault("text", "")).strip();
        require(!text.isBlank() && text.length() <= 240, "BAD_GUESS", "use a guess of 1–240 characters");
        boolean correct = normalizeText(text).equals(normalizeText(d.currentWord));
        d.emit("TEXT_GUESS", Map.of("from", a.actor(), "text", text, "correct", correct,
                "wordIndex", d.usedWords.size()));
        if (correct) record(d, true, false, a.actor(), s.currentDescriber());
    }

    private static String normalizeText(String text) {
        return java.text.Normalizer.normalize(text.toLowerCase(java.util.Locale.ROOT), java.text.Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "").replaceAll("[^\\p{L}\\p{N}]", "");
    }

    /** The describer giving up on a word — no point, but it still counts as an attempt. */
    private void skip(WordBluffState.Draft d, WordBluffState s, PlayerAction a) {
        require(d.phase.equals("Turn"), "WRONG_PHASE", "SKIP is Turn-only");
        require(a.actor().equals(s.currentDescriber()), "NOT_YOUR_TURN", "only the describer skips");
        require(d.currentWord != null, "NO_ACTIVE_WORD", "reveal a word first");
        record(d, false, true, a.actor(), s.currentDescriber());
    }

    /**
     * Files the word as an attempt. Deliberately does *not* touch the score:
     * nothing counts until both teams accept the review at the end of the
     * turn (see {@link #commitReview}).
     */
    private void record(WordBluffState.Draft d, boolean correct, boolean skipped, String by, String describer) {
        String word = d.currentWord;
        Category category = d.currentCategory;
        d.usedWords.add(word);
        d.turnAttempts.add(new WordBluffState.Attempt(word, category.slug(), correct, skipped, by));
        d.emit("WORD_RESOLVED", Map.of(
                "result", skipped ? "skipped" : (correct ? "correct" : "wrong"),
                "word", word,
                "category", category.slug(),
                "markedBy", by,
                "wordIndex", d.usedWords.size(),
                "attempted", d.turnAttempts.size(),
                "correctSoFar", correctCount(d.turnAttempts)));
        // The category belongs to the turn, so it stays put — only the word
        // moves on. Skipping a hard one should put the next straight up
        // while the clock is still running.
        d.currentWord = null;
        if ("Turn".equals(d.phase)) {
            try {
                revealNextWord(d, describer);
            } catch (RuleViolation e) {
                // Every word in the bank has been used this session. The
                // turn simply runs out of words rather than blowing up
                // half way through resolving one — the resolve above has
                // already been emitted and must stand.
                d.currentWord = null;
            }
        }
    }

    /** Flips one call during review — either side may correct either way. */
    private void reviewToggle(WordBluffState.Draft d, WordBluffState s, PlayerAction a) {
        require(d.phase.equals("Review"), "WRONG_PHASE", "corrections are Review-only");
        require(s.teamOfPlayer(a.actor()) != null, "NOT_A_PLAYER", "only players can correct a call");
        int index = a.data().get("index") instanceof Number n ? n.intValue() : -1;
        require(index >= 0 && index < d.turnAttempts.size(), "BAD_INDEX", "no attempt at index " + index);

        WordBluffState.Attempt flipped = d.turnAttempts.get(index).flipped(a.actor());
        d.turnAttempts.set(index, flipped);
        // A correction invalidates any sign-off already given — both sides
        // must accept the numbers they're actually committing to.
        d.reviewAccepted.clear();
        d.emit("REVIEW_CORRECTED", Map.of(
                "index", index,
                "word", flipped.word(),
                "correct", flipped.correct(),
                "by", a.actor(),
                "correctSoFar", correctCount(d.turnAttempts)));
    }

    /** One accept per team; the second one starts a short score recap. */
    private void reviewAccept(WordBluffState.Draft d, WordBluffState s, PlayerAction a) {
        require(d.phase.equals("Review"), "WRONG_PHASE", "accepting is Review-only");
        String team = s.teamOfPlayer(a.actor());
        require(team != null, "NOT_A_PLAYER", "only players can accept the review");
        require(!d.reviewAccepted.contains(team), "ALREADY_ACCEPTED", "your team already accepted");

        d.reviewAccepted.add(team);
        d.emit("REVIEW_ACCEPTED", Map.of("team", team, "by", a.actor(), "accepted", List.copyOf(d.reviewAccepted)));
        if (d.reviewAccepted.size() >= 2) {
            d.phase = "Summary";
            d.emit("REVIEW_FINALIZED", Map.of("scored", correctCount(d.turnAttempts),
                    "attempted", d.turnAttempts.size()));
        }
    }

    /** Both sides signed off: the turn's correct count becomes real score. */
    private void commitReview(WordBluffState.Draft d) {
        int scored = correctCount(d.turnAttempts);
        int attempted = d.turnAttempts.size();
        if (WordBluffState.TEAM_A.equals(d.turnTeam)) {
            d.teamAScore += scored;
        } else {
            d.teamBScore += scored;
        }
        d.emit("TURN_COMMITTED", Map.of(
                "team", d.turnTeam,
                "scored", scored,
                "attempted", attempted,
                "teamAScore", d.teamAScore,
                "teamBScore", d.teamBScore));

        if (d.teamAScore >= d.config.targetScore()) {
            finish(d, WordBluffState.TEAM_A);
        } else if (d.teamBScore >= d.config.targetScore()) {
            finish(d, WordBluffState.TEAM_B);
        } else {
            rotateToNextTeam(d);
            d.round++;
            d.phase = "Turn";
            startTurn(d);
        }
    }

    private static int correctCount(List<WordBluffState.Attempt> attempts) {
        return (int) attempts.stream().filter(WordBluffState.Attempt::correct).count();
    }

    // ---------------------------------------------------------------- phase machine

    private void advance(WordBluffState.Draft d, String from) {
        switch (from) {
            case "Turn" -> endTurn(d);
            // Review only leaves on both teams accepting (see reviewAccept).
            // A forced ADVANCE_PHASE here commits what's on screen rather
            // than stranding the turn — the timer must never deadlock a game
            // just because one side went quiet.
            case "Review" -> commitReview(d);
            case "Summary" -> commitReview(d);
            case "Results" -> { /* terminal */ }
            default -> throw new RuleViolation("BAD_PHASE", "cannot advance from " + from);
        }
    }

    private void startTurn(WordBluffState.Draft d) {
        d.currentCategory = null;
        d.clockStarted = false;
        d.currentWord = null;
        d.turnAttempts.clear();
        d.reviewAccepted.clear();
        d.emit("TURN_STARTED", Map.of(
                "team", d.turnTeam,
                "describer", d.turnTeam.equals(WordBluffState.TEAM_A) ? d.teamA.get(d.describerIndexA % d.teamA.size())
                        : d.teamB.get(d.describerIndexB % d.teamB.size()),
                "round", d.round));
    }

    /**
     * The clock ran out. Nothing scores yet — the turn's attempts go to both
     * teams for review, and only an agreed set of marks becomes score. A word
     * still revealed at zero is abandoned rather than counted, same as a real
     * timer cutting someone off mid-description.
     */
    private void endTurn(WordBluffState.Draft d) {
        d.currentCategory = null;
        d.currentWord = null;
        d.phase = "Review";
        d.reviewAccepted.clear();
        d.emit("TURN_ENDED", Map.of(
                "team", d.turnTeam,
                "attempted", d.turnAttempts.size(),
                "proposedScore", correctCount(d.turnAttempts),
                "attempts", attemptsPayload(d.turnAttempts),
                "teamAScore", d.teamAScore,
                "teamBScore", d.teamBScore));
    }

    private static List<Map<String, Object>> attemptsPayload(List<WordBluffState.Attempt> attempts) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (int i = 0; i < attempts.size(); i++) {
            WordBluffState.Attempt at = attempts.get(i);
            out.add(Map.of(
                    "index", i,
                    "word", at.word(),
                    "category", at.category(),
                    "correct", at.correct(),
                    "skipped", at.skipped()));
        }
        return out;
    }

    private void rotateToNextTeam(WordBluffState.Draft d) {
        // the team that just went rotates its describer for its *next* turn;
        // the team about to go keeps whichever describer is already queued.
        if (WordBluffState.TEAM_A.equals(d.turnTeam)) {
            d.describerIndexA++;
        } else {
            d.describerIndexB++;
        }
        d.turnTeam = d.turnTeam.equals(WordBluffState.TEAM_A) ? WordBluffState.TEAM_B : WordBluffState.TEAM_A;
    }

    private void finish(WordBluffState.Draft d, String winningTeam) {
        Map<String, String> outcome = new LinkedHashMap<>();
        for (String id : d.teamA) {
            outcome.put(id, winningTeam.equals(WordBluffState.TEAM_A) ? "won" : "lost");
        }
        for (String id : d.teamB) {
            outcome.put(id, winningTeam.equals(WordBluffState.TEAM_B) ? "won" : "lost");
        }
        d.win = new WinResult(winningTeam, outcome);
        d.phase = "Results";
        d.emit("GAME_OVER", Map.of(
                "winningTeam", winningTeam,
                "teamAScore", d.teamAScore,
                "teamBScore", d.teamBScore,
                "rounds", d.round));
    }

    private void forfeit(WordBluffState.Draft d, WordBluffState s, PlayerAction action) {
        String team = s.teamOfPlayer(action.actor());
        require(team != null, "NOT_A_PLAYER", "only a player can forfeit");
        finish(d, s.otherTeam(team));
    }

    // ---------------------------------------------------------------- win + views

    @Override
    public java.util.Optional<WinResult> checkWinCondition(GameState state) {
        return java.util.Optional.ofNullable(((WordBluffState) state).win);
    }

    @Override
    public java.util.Set<String> playersToAct(GameState state) {
        WordBluffState s = (WordBluffState) state;
        if (s.finished()) return java.util.Set.of();
        if ("Turn".equals(s.phase())) return java.util.Set.of(s.currentDescriber());
        if ("Review".equals(s.phase())) {
            // Any member of a not-yet-accepted team can accept on its behalf
            // (see WordBluffModule.reviewAccept) — so everyone on that team
            // is a valid "needs to act" target, not just one designated player.
            java.util.Set<String> toAct = new java.util.LinkedHashSet<>();
            if (!s.reviewAccepted.contains(WordBluffState.TEAM_A)) toAct.addAll(s.teamOf(WordBluffState.TEAM_A));
            if (!s.reviewAccepted.contains(WordBluffState.TEAM_B)) toAct.addAll(s.teamOf(WordBluffState.TEAM_B));
            return toAct;
        }
        return java.util.Set.of(); // Summary is a brief timed recap, no player action needed
    }

    @Override
    public PlayerVisibleState visibleStateFor(GameState state, String playerId) {
        WordBluffState s = (WordBluffState) state;
        Map<String, Object> m = commonView(s);
        // Judges receive the word in the live event and need it on reconnect.
        if (s.currentWord != null && (playerId.equals(s.currentDescriber())
                || s.otherTeam(s.turnTeam).equals(s.teamOfPlayer(playerId)))) {
            m.put("yourWord", s.currentWord);
        }
        return new PlayerVisibleState(m);
    }

    @Override
    public PublicBroadcastState broadcastState(GameState state) {
        return new PublicBroadcastState(commonView((WordBluffState) state));
    }

    /** Fields safe for anyone — never includes {@code currentWord}, only whoever's describing knows it. */
    private Map<String, Object> commonView(WordBluffState s) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("phase", s.phase);
        m.put("textMode", s.config.textMode());
        m.put("wordIndex", s.usedWords.size());
        m.put("round", s.round);
        m.put("teamA", s.teamA);
        m.put("teamB", s.teamB);
        m.put("teamAScore", s.teamAScore);
        m.put("teamBScore", s.teamBScore);
        m.put("turnTeam", s.turnTeam);
        m.put("describer", s.currentDescriber());
        m.put("hasActiveCategory", s.currentCategory != null);
        m.put("clockStarted", s.clockStarted);
        if (s.currentCategory != null) {
            m.put("category", s.currentCategory.slug());
        }
        m.put("hasActiveWord", s.currentWord != null);
        m.put("targetScore", s.config.targetScore());
        m.put("turnSeconds", s.config.turnSeconds());
        // The turn's running tally, and — once the clock stops — the full
        // list everyone reviews together before it becomes score.
        m.put("attempted", s.turnAttempts.size());
        m.put("proposedScore", correctCount(s.turnAttempts));
        m.put("attempts", attemptsPayload(s.turnAttempts));
        m.put("reviewAccepted", List.copyOf(s.reviewAccepted));
        if (s.finished()) m.put("winningTeam", s.win.winningSide());
        return m;
    }

    @Override
    public List<GameEvent> drainEvents(GameState prev, GameState next) {
        List<GameEvent> a = ((WordBluffState) prev).events();
        List<GameEvent> b = ((WordBluffState) next).events();
        return b.subList(a.size(), b.size());
    }

    // ---------------------------------------------------------------- helpers

    private RandomSource drawRng(WordBluffState.Draft d) {
        return RandomSource.seeded(d.seed + 7919L * ++d.drawCounter);
    }

    private static void require(boolean condition, String code, String message) {
        if (!condition) {
            throw new RuleViolation(code, message);
        }
    }
}
