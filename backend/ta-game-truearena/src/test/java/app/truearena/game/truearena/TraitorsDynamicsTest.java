package app.truearena.game.truearena;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** The dynamics (docs/TRAITORS_DYNAMICS_PLAN.md): recruiting, the pie, clues, alibis, the lantern, the spot, Last Stand, the Ghost Jury and the crowd. */
class TraitorsDynamicsTest {

    private final TrueArenaModule module = new TrueArenaModule();

    // ---------------------------------------------------------------- set-up and play helpers

    private static List<String> ids(int n) {
        return IntStream.rangeClosed(1, n).mapToObj(i -> "p" + i).toList();
    }

    private static GameConfig with(GameConfig b, String tieBreak, GameConfig.Table table, Map<String, Map<String, Object>> twists) {
        return new GameConfig(b.catalogVersion(), b.preset(), table, b.timers(), b.nightKill(), b.revealOnElimination(),
                tieBreak, b.secondTie(), b.suddenDeathSeconds(), b.afk(), b.voteReveal(), b.endgameVeil(), twists);
    }

    /** Classic's rules with only the given twists — so one twist is tested on its own. */
    private static GameConfig classic(int players, int traitors, String tieBreak, Map<String, Map<String, Object>> twists) {
        return with(Presets.CLASSIC_CONSPIRACY.config(), tieBreak,
                new GameConfig.Table(players, 4, 16, true, List.of(List.of(4, traitors))), twists);
    }

    private TruearenaState start(GameConfig config, int players, long seed) {
        return (TruearenaState) module.initialState(ids(players), config, RandomSource.seeded(seed));
    }

    private TruearenaState act(TruearenaState s, String actor, String type, Map<String, Object> data) {
        return (TruearenaState) module.onPlayerAction(s, PlayerAction.of(actor, type, data));
    }

    private TruearenaState elapse(TruearenaState s) {
        return (TruearenaState) module.onPhaseElapsed(s, s.phase);
    }

    private TruearenaState until(TruearenaState s, String phase) {
        for (int guard = 0; !phase.equals(s.phase) && !s.finished() && guard < 40; guard++) s = elapse(s);
        assertThat(s.phase).as("reached %s", phase).isEqualTo(phase);
        return s;
    }

    private List<GameEvent> events(TruearenaState before, TruearenaState after) {
        return module.drainEvents(before, after);
    }

    private static GameEvent only(List<GameEvent> events, String type) {
        List<GameEvent> found = events.stream().filter(e -> e.type().equals(type)).toList();
        assertThat(found).as("one %s", type).hasSize(1);
        return found.getFirst();
    }

    @SuppressWarnings("unchecked")
    private static List<String> strings(Object list) {
        return (List<String>) list;
    }

    private static List<String> types(List<GameEvent> events) {
        return events.stream().map(GameEvent::type).toList();
    }

    private static List<String> traitors(TruearenaState s) {
        return s.aliveTraitors().stream().sorted().toList();
    }

    private static List<String> faithful(TruearenaState s) {
        return s.aliveFaithful().stream().sorted().toList();
    }

    /** Every living Traitor picks {@code victim}; the night ends once everyone it needs has acted (or the clock). */
    private TruearenaState murder(TruearenaState s, String victim) {
        s = until(s, "Night");
        for (String t : traitors(s)) {
            if ("Night".equals(s.phase)) s = act(s, t, "NIGHT_TARGET", Map.of("target", victim));
        }
        return "Night".equals(s.phase) ? elapse(s) : s;
    }

    /** Everyone listed votes; anyone else abstains. Plays on through the review to whatever follows the tally. */
    private TruearenaState vote(TruearenaState s, Map<String, String> ballots) {
        s = until(s, "Vote");
        for (var b : ballots.entrySet()) {
            if ("Vote".equals(s.phase)) s = act(s, b.getKey(), "CAST_VOTE", Map.of("target", b.getValue()));
        }
        while (List.of("Vote", "VoteReview", "Elimination").contains(s.phase) && !s.finished()) s = elapse(s);
        return s;
    }

    private TruearenaState banish(TruearenaState s, String who) {
        Map<String, String> ballots = new LinkedHashMap<>();
        for (String voter : s.alive) {
            if (!voter.equals(who)) ballots.put(voter, who);
        }
        String other = s.alive.stream().filter(id -> !id.equals(who)).findFirst().orElseThrow();
        ballots.put(who, other);
        return vote(s, ballots);
    }

    private Map<String, Object> view(TruearenaState s, String who) {
        return module.visibleStateFor(s, who).data();
    }

    private Map<String, Object> broadcast(TruearenaState s) {
        return module.broadcastState(s).data();
    }

    // ---------------------------------------------------------------- recruiting

    /** A crafted table: {@code alive} players, the first {@code living} of them Traitors, {@code original} at the start. */
    private static TruearenaState table(GameConfig config, int alive, int living, int original) {
        TruearenaState.Draft d = new TruearenaState.Draft();
        d.config = config;
        d.phase = "Night";
        d.players = new ArrayList<>(ids(alive + original));
        for (int i = 0; i < alive; i++) {
            String id = "p" + (i + 1);
            d.alive.add(id);
            d.roles.put(id, i < living ? TruearenaState.TRAITOR : TruearenaState.FAITHFUL);
            if (i < living) d.originalTraitors.add(id);
        }
        // The fallen Traitors make up the starting number.
        for (int i = alive; d.originalTraitors.size() < original; i++) {
            String id = "p" + (i + 1);
            d.roles.put(id, TruearenaState.TRAITOR);
            d.originalTraitors.add(id);
            d.eliminatedLog.add(id);
        }
        return d.build();
    }

    @Test void recruitingOpensOnceATraitorFalls_neverPastTwoFaithfulPerTraitorOrTheStartingNumber() {
        GameConfig heist = Presets.MIDNIGHT_HEIST.config();
        assertThat(TrueArenaModule.recruitOpen(table(heist, 12, 3, 3))).as("all three still alive").isFalse();
        assertThat(TrueArenaModule.recruitOpen(table(heist, 11, 2, 3))).as("one lost, 11 at the table").isTrue();
        assertThat(TrueArenaModule.recruitOpen(table(heist, 8, 2, 3))).as("a third would break 2-to-1").isFalse();
        assertThat(TrueArenaModule.recruitOpen(table(heist, 8, 1, 3))).as("back up to two").isTrue();
        assertThat(TrueArenaModule.recruitOpen(table(heist, 6, 1, 2))).as("two Traitors down to the last six").isTrue();
        assertThat(TrueArenaModule.recruitOpen(table(heist, 5, 1, 3))).as("closed at five").isFalse();
        assertThat(TrueArenaModule.recruitOpen(table(heist, 9, 0, 3))).as("nobody left to recruit").isFalse();
        assertThat(TrueArenaModule.recruitOpen(table(Presets.CLASSIC_CONSPIRACY.config(), 11, 2, 3)))
                .as("Classic never recruits").isFalse();
    }

    /** Midnight Heist, 12 players, three Traitors: a quiet first night, then the first Traitor is banished. */
    private TruearenaState heistAfterLosingATraitor(long seed) {
        TruearenaState s = start(Presets.MIDNIGHT_HEIST.config(), 12, seed);
        assertThat(traitors(s)).hasSize(3);
        s = until(s, "Night");
        s = elapse(s); // nobody picked: nobody dies
        s = banish(s, traitors(s).getFirst());
        return until(s, "Night");
    }

    @Test void anAnonymousOfferReplacesTheMurder_andAcceptingMakesANewTraitor() {
        TruearenaState s = heistAfterLosingATraitor(11);
        String recruiter = traitors(s).getFirst();
        String target = faithful(s).getFirst();
        assertThat(view(s, recruiter)).containsEntry("canRecruit", true);
        assertThat(strings(view(s, recruiter).get("recruitTargets"))).contains(target);
        assertThat(view(s, target)).doesNotContainKey("canRecruit");

        TruearenaState before = s;
        s = act(s, recruiter, "RECRUIT_OFFER", Map.of("target", target));
        List<GameEvent> dawn = events(before, s);
        assertThat(s.phase).as("nothing else to wait for").isEqualTo("MorningReveal");
        assertThat(only(dawn, "NO_MURDER").payload()).containsEntry("reason", "recruiting");
        assertThat(types(dawn)).doesNotContain("PLAYER_ELIMINATED");
        GameEvent offer = only(dawn, "RECRUIT_OFFER");
        assertThat(offer.visibility()).isEqualTo(GameEvent.Visibility.player(target));
        assertThat(offer.payload()).as("the offer never says who sent it").containsOnlyKeys("round");
        assertThat(view(s, target)).containsEntry("recruitOffer", true);
        assertThat(view(s, faithful(s).get(1))).doesNotContainKey("recruitOffer");

        before = s;
        s = act(s, target, "RECRUIT_ANSWER", Map.of("accept", true));
        assertThat(s.isTraitor(target)).isTrue();
        assertThat(s.roles.get(target)).isEqualTo(TruearenaState.RECRUITED);
        List<GameEvent> joined = events(before, s);
        assertThat(strings(only(joined, "FELLOW_TRAITORS").payload().get("ids"))).containsExactlyInAnyOrderElementsOf(
                traitors(s).stream().filter(id -> !id.equals(target)).toList());
        assertThat(only(joined, "RECRUIT_ACCEPTED").visibility()).isEqualTo(GameEvent.Visibility.role(TruearenaState.TRAITOR));
        assertThat(view(s, target)).containsKey("fellowTraitors");
    }

    @Test void refusingStaysFaithful_silenceIsARefusal_andNobodyIsAskedTwice() {
        TruearenaState s = heistAfterLosingATraitor(12);
        String recruiter = traitors(s).getFirst();
        String first = faithful(s).getFirst();
        s = act(s, recruiter, "RECRUIT_OFFER", Map.of("target", first));
        TruearenaState before = s;
        s = act(s, first, "RECRUIT_ANSWER", Map.of("accept", false));
        assertThat(s.isTraitor(first)).isFalse();
        assertThat(only(events(before, s), "RECRUIT_REFUSED").payload()).containsEntry("reason", "refused");

        // The day passes with nobody banished; the next night they try someone else, who never answers.
        s = vote(s, Map.of());
        s = until(s, "Night");
        assertThat(strings(view(s, recruiter).get("recruitTargets"))).doesNotContain(first);
        TruearenaState night = s;
        assertThatThrownBy(() -> act(night, recruiter, "RECRUIT_OFFER", Map.of("target", first)))
                .as("nobody is asked twice").isInstanceOf(RuleViolation.class);
        String second = faithful(s).get(1);
        s = act(s, recruiter, "RECRUIT_OFFER", Map.of("target", second));
        before = s;
        s = until(s, "Vote");
        List<GameEvent> lapsed = events(before, s);
        assertThat(only(lapsed, "RECRUIT_REFUSED").payload()).containsEntry("reason", "no_answer");
        assertThat(only(lapsed, "RECRUIT_EXPIRED").visibility()).isEqualTo(GameEvent.Visibility.player(second));
        assertThat(s.isTraitor(second)).isFalse();
    }

    @Test void onARecruitingNightTheTraitorsCannotAlsoMurder() {
        TruearenaState s = heistAfterLosingATraitor(13);
        List<String> t = traitors(s);
        // One Traitor picks a target first; the offer clears it — tonight is for recruiting.
        s = act(s, t.getFirst(), "NIGHT_TARGET", Map.of("target", faithful(s).get(2)));
        s = act(s, t.get(1), "RECRUIT_OFFER", Map.of("target", faithful(s).getFirst()));
        assertThat(s.phase).isEqualTo("MorningReveal");
        assertThat(s.alive).hasSize(11);
    }

    // ---------------------------------------------------------------- the Poisoned Pie

    private TruearenaState heistWithPie(String filling, long seed) {
        TruearenaState s = until(start(Presets.MIDNIGHT_HEIST.config(), 10, seed), "Night");
        String baker = traitors(s).getFirst();
        assertThat(view(s, baker)).containsEntry("canBakePie", true);
        s = act(s, baker, "BAKE_PIE", Map.of("filling", filling));
        assertThat(view(s, baker)).containsEntry("pieBakedTonight", filling);
        assertThat(view(s, faithful(s).getFirst())).doesNotContainKey("pieBakedTonight");
        return s;
    }

    @Test void thePieComesWithAClue_andARealOneSavesWhoeverTookIt() {
        TruearenaState s = heistWithPie("shield", 21);
        String victim = faithful(s).getLast();
        TruearenaState before = s;
        s = murder(s, victim);
        GameEvent served = only(events(before, s), "PIE_SERVED");
        String clue = (String) served.payload().get("clue");
        assertThat(TrueArenaModule.SHIELD_CLUES.contains(clue) || TrueArenaModule.POISON_CLUES.contains(clue)).isTrue();
        @SuppressWarnings("unchecked") Map<String, Object> pie = (Map<String, Object>) broadcast(s).get("pie");
        assertThat(pie).containsEntry("available", true).containsEntry("clue", clue);

        s = until(s, "RoundTable");
        String eater = faithful(s).getFirst();
        s = act(s, eater, "TAKE_PIE", Map.of());
        assertThatThrownBy(sTake(s, faithful(s).get(1))).isInstanceOf(RuleViolation.class);
        s = vote(s, Map.of());
        before = until(s, "Night");
        s = murder(before, eater);
        List<GameEvent> dawn = events(before, s);
        assertThat(only(dawn, "PIE_SAVED").payload()).containsEntry("holder", eater);
        assertThat(only(dawn, "PIE_REVEALED").payload()).containsEntry("filling", "shield");
        assertThat(s.alive).contains(eater);
    }

    private org.assertj.core.api.ThrowableAssert.ThrowingCallable sTake(TruearenaState s, String who) {
        return () -> act(s, who, "TAKE_PIE", Map.of());
    }

    @Test void aPoisonedPieTakesItsEaterTheNextNight_andAPieNobodyTakesSpoils() {
        TruearenaState s = heistWithPie("poison", 22);
        s = murder(s, faithful(s).getLast());
        s = until(s, "RoundTable");
        String eater = faithful(s).getFirst();
        s = act(s, eater, "TAKE_PIE", Map.of());
        s = vote(s, Map.of());
        TruearenaState before = until(s, "Night");
        s = murder(before, faithful(before).get(1));
        List<GameEvent> dawn = events(before, s);
        assertThat(only(dawn, "PIE_REVEALED").payload()).containsEntry("filling", "poison").containsEntry("holder", eater);
        assertThat(s.eliminationCause).containsEntry(eater, "poison");

        TruearenaState spoiled = heistWithPie("shield", 23);
        spoiled = murder(spoiled, faithful(spoiled).getLast());
        before = until(spoiled, "RoundTable");
        spoiled = until(before, "Vote");
        assertThat(only(events(before, spoiled), "PIE_SPOILED").payload()).containsEntry("filling", "shield");
    }

    @Test void thePiesClueTellsTheTruthAboutTwoTimesInThree() {
        int honest = 0, games = 300;
        for (long seed = 1; seed <= games; seed++) {
            TruearenaState s = heistWithPie(seed % 2 == 0 ? "shield" : "poison", seed);
            TruearenaState before = s;
            s = murder(s, faithful(s).getLast());
            String clue = (String) only(events(before, s), "PIE_SERVED").payload().get("clue");
            boolean looksPoisoned = TrueArenaModule.POISON_CLUES.contains(clue);
            if (looksPoisoned == s.piePoisoned) honest++;
        }
        assertThat(honest / (double) games).isBetween(0.57, 0.77);
    }

    // ---------------------------------------------------------------- Crime-Scene Clues

    @Test void everyMurderLeavesOneClue_andEveryClueIsTrue() {
        GameConfig config = classic(10, 3, "revote", Map.of("crime_clues", Map.of()));
        for (long seed = 1; seed <= 80; seed++) {
            TruearenaState s = until(start(config, 10, seed), "Night");
            // A day of votes first, so the "who a Traitor voted for" clue has something to draw on.
            s = vote(elapse(s), Map.of(traitors(s).getFirst(), faithful(s).get(3)));
            s = until(s, "Night");
            String victim = faithful(s).getFirst();
            TruearenaState before = s;
            s = murder(s, victim);
            Map<String, Object> clue = only(events(before, s), "CRIME_CLUE").payload();
            assertThat(clue).containsEntry("victim", victim);
            List<String> living = s.aliveTraitors();
            TruearenaState dawn = s;
            switch ((String) clue.get("kind")) {
                case "seat" -> {
                    int n = s.players.size(), at = s.players.indexOf(victim), within = (int) clue.get("within");
                    assertThat(living).as("seed %d: a Traitor within %d seats", seed, within).anyMatch(t -> {
                        int gap = Math.abs(dawn.players.indexOf(t) - at);
                        return Math.min(gap, n - gap) <= within;
                    });
                }
                case "trio" -> {
                    @SuppressWarnings("unchecked") List<String> trio = (List<String>) clue.get("ids");
                    assertThat(trio).hasSize(3).anyMatch(dawn::isTraitor);
                }
                case "vote" -> {
                    String target = (String) clue.get("target");
                    assertThat(s.isTraitor(target)).isFalse();
                    @SuppressWarnings("unchecked") Map<String, String> last =
                            (Map<String, String>) s.ballotHistory.getLast().get("votes");
                    assertThat(living).anyMatch(t -> target.equals(last.get(t)));
                }
                default -> throw new AssertionError("unknown clue " + clue);
            }
            assertThat((List<?>) broadcast(s).get("crimeClues")).hasSize(1);
        }
    }

    // ---------------------------------------------------------------- Alibis

    @Test void theNightWaitsForEveryAlibi_thenTheMorningShowsThemAll() {
        TruearenaState s = until(start(classic(8, 2, "revote", Map.of("alibis", Map.of())), 8, 31), "Night");
        String victim = faithful(s).getFirst();
        for (String t : traitors(s)) s = act(s, t, "NIGHT_TARGET", Map.of("target", victim));
        assertThat(s.phase).as("still waiting on alibis").isEqualTo("Night");
        assertThat(view(s, victim)).containsEntry("alibiNeeded", true);
        List<String> living = s.alive.stream().toList();
        TruearenaState before = s;
        for (int i = 0; i < living.size(); i++) {
            String with = living.get((i + 1) % living.size());
            s = act(s, living.get(i), "ALIBI", Map.of("with", with));
        }
        assertThat(s.phase).isEqualTo("MorningReveal");
        @SuppressWarnings("unchecked") Map<String, String> board =
                (Map<String, String>) only(events(before, s), "ALIBIS_REVEALED").payload().get("alibis");
        assertThat(board).hasSize(living.size()).containsEntry(living.get(0), living.get(1));
        assertThat(broadcast(s)).containsKey("alibiBoard");
        TruearenaState fresh = until(start(classic(8, 2, "revote", Map.of("alibis", Map.of())), 8, 31), "Night");
        assertThatThrownBy(() -> act(fresh, "p1", "ALIBI", Map.of("with", "p1"))).as("not with yourself").isInstanceOf(RuleViolation.class);
    }

    // ---------------------------------------------------------------- the Seer's Lantern

    @Test void theSeerSeesOneTrueSide_once_andTheNightWaitsForTheLantern() {
        TruearenaState s = until(start(classic(8, 2, "revote", Map.of("seer_lantern", Map.of())), 8, 41), "Night");
        String seer = s.seer;
        assertThat(seer).isNotNull();
        assertThat(s.isTraitor(seer)).isFalse();
        @SuppressWarnings("unchecked") Map<String, Object> lantern = (Map<String, Object>) view(s, seer).get("seer");
        assertThat(lantern).containsEntry("canLight", true);
        assertThat(view(s, faithful(s).stream().filter(id -> !id.equals(seer)).findFirst().orElseThrow())).doesNotContainKey("seer");

        String victim = faithful(s).stream().filter(id -> !id.equals(seer)).findFirst().orElseThrow();
        for (String t : traitors(s)) s = act(s, t, "NIGHT_TARGET", Map.of("target", victim));
        assertThat(s.phase).as("the night waits for the lantern").isEqualTo("Night");
        String suspect = traitors(s).getFirst();
        TruearenaState before = s;
        s = act(s, seer, "SEER_LANTERN", Map.of("target", suspect));
        GameEvent vision = only(events(before, s), "LANTERN_VISION");
        assertThat(vision.visibility()).isEqualTo(GameEvent.Visibility.player(seer));
        assertThat(vision.payload()).containsEntry("target", suspect).containsEntry("side", "traitor");
        assertThat(s.phase).isEqualTo("MorningReveal");

        // Next night the lantern is spent: the Traitors' pick ends the night on its own.
        s = vote(s, Map.of());
        s = until(s, "Night");
        TruearenaState night = s;
        assertThatThrownBy(() -> act(night, seer, "SEER_LANTERN", Map.of("target", faithful(night).getLast())))
                .isInstanceOf(RuleViolation.class);
        for (String t : traitors(s)) s = act(s, t, "NIGHT_TARGET", Map.of("target", faithful(s).getLast()));
        assertThat(s.phase).isEqualTo("MorningReveal");
    }

    @Test void theSeerCanKeepTheLanternForAnotherNight() {
        TruearenaState s = until(start(classic(8, 2, "revote", Map.of("seer_lantern", Map.of())), 8, 42), "Night");
        String seer = s.seer;
        s = act(s, seer, "SEER_LANTERN", Map.of());
        String victim = faithful(s).stream().filter(id -> !id.equals(seer)).findFirst().orElseThrow();
        for (String t : traitors(s)) s = act(s, t, "NIGHT_TARGET", Map.of("target", victim));
        assertThat(s.phase).isEqualTo("MorningReveal");
        assertThat(s.lanternUsed).isFalse();
    }

    // ---------------------------------------------------------------- the Black Spot

    @Test void theBlackSpotTravels_neverBack_andTakesItsHoldersVote() {
        TruearenaState s = until(start(classic(8, 2, "revote", Map.of("black_spot", Map.of())), 8, 51), "Night");
        String marked = faithful(s).getFirst();
        s = act(s, traitors(s).getFirst(), "PLACE_SPOT", Map.of("target", marked));
        TruearenaState before = s;
        s = murder(s, faithful(s).getLast());
        assertThat(only(events(before, s), "BLACK_SPOT_MARKED").payload()).containsEntry("holder", marked);

        s = until(s, "RoundTable");
        String next = faithful(s).get(1);
        s = act(s, marked, "PASS_SPOT", Map.of("to", next));
        TruearenaState passed = s;
        assertThatThrownBy(() -> act(passed, next, "PASS_SPOT", Map.of("to", marked))).as("never back").isInstanceOf(RuleViolation.class);
        assertThatThrownBy(() -> act(passed, marked, "PASS_SPOT", Map.of("to", faithful(passed).get(2))))
                .as("only the holder passes").isInstanceOf(RuleViolation.class);
        @SuppressWarnings("unchecked") Map<String, Object> spot = (Map<String, Object>) broadcast(s).get("blackSpot");
        assertThat(spot).containsEntry("holder", next).containsEntry("chain", List.of(marked, next));

        before = s;
        s = until(s, "Vote");
        assertThat(only(events(before, s), "BLACK_SPOT_SILENCED").payload()).containsEntry("holder", next);
        TruearenaState voting = s;
        assertThatThrownBy(() -> act(voting, next, "CAST_VOTE", Map.of("target", marked))).isInstanceOf(RuleViolation.class);
        // Everyone else voting closes the ballot without them.
        for (String voter : s.alive) {
            if (!voter.equals(next)) s = act(s, voter, "CAST_VOTE", Map.of("target", voter.equals(marked) ? next : marked));
        }
        assertThat(s.phase).isEqualTo("VoteReview");
    }

    // ---------------------------------------------------------------- Last Stand

    @Test void aLastStandAtTheFinalFourShowsOneTrueSide_andCostsTheirPlace() {
        GameConfig gambit = with(Presets.FINAL_GAMBIT.config(), "no_elimination",
                new GameConfig.Table(4, 4, 8, true, List.of(List.of(4, 1))), Map.of("last_stand", Map.of()));
        TruearenaState s = until(start(gambit, 4, 61), "RoundTable");
        String hero = faithful(s).getFirst();
        String traitor = traitors(s).getFirst();
        assertThat(view(s, hero)).containsEntry("canLastStand", true);
        TruearenaState before = s;
        s = act(s, hero, "LAST_STAND", Map.of("target", traitor));
        assertThat(only(events(before, s), "LAST_STAND").payload())
                .containsEntry("target", traitor).containsEntry("side", "traitor").doesNotContainKey("role");
        assertThat(s.alive).doesNotContain(hero);
        assertThat(s.eliminationCause).containsEntry(hero, "last_stand");
        assertThat(broadcast(s).get("standReveal")).isEqualTo(Map.of("by", hero, "target", traitor, "side", "traitor"));
        TruearenaState after = s;
        assertThatThrownBy(() -> act(after, faithful(after).getFirst(), "LAST_STAND", Map.of("target", traitor)))
                .as("once a game").isInstanceOf(RuleViolation.class);

        GameConfig five = with(Presets.FINAL_GAMBIT.config(), "no_elimination",
                new GameConfig.Table(5, 4, 8, true, List.of(List.of(4, 1))), Map.of("last_stand", Map.of()));
        TruearenaState early = until(start(five, 5, 62), "RoundTable");
        assertThatThrownBy(() -> act(early, faithful(early).getFirst(), "LAST_STAND", Map.of("target", traitors(early).getFirst())))
                .as("not before the final four").isInstanceOf(RuleViolation.class);
    }

    // ---------------------------------------------------------------- the Ghost Jury

    /**
     * Eight players, two Traitors: one Faithful murdered (a plain ghost); one who voted for a
     * real Traitor, then murdered (a Super Faithful); a day-two vote tied between two players.
     */
    private record JuryTable(TruearenaState state, String plainGhost, String superGhost, String a, String b) {
    }

    private JuryTable juryTable(String tieBreak, Map<String, Map<String, Object>> twists, long seed) {
        TruearenaState s = until(start(classic(8, 2, tieBreak, twists), 8, seed), "Night");
        List<String> f = faithful(s);
        String plain = f.get(0), sharp = f.get(1);
        s = murder(s, plain);
        // Day one: only the sharp Faithful votes — for a real Traitor, who is banished.
        String traitor = traitors(s).getFirst();
        s = vote(s, Map.of(sharp, traitor));
        assertThat(s.alive).doesNotContain(traitor);
        assertThat(s.rightVoters).contains(sharp);
        s = murder(until(s, "Night"), sharp);
        // Day two: five left, tied 2–2 between A and B.
        List<String> left = s.alive.stream().sorted().toList();
        String a = left.get(0), b = left.get(1);
        Map<String, String> ballots = new LinkedHashMap<>();
        ballots.put(left.get(2), a);
        ballots.put(left.get(3), a);
        ballots.put(left.get(4), b);
        ballots.put(a, b);
        ballots.put(b, left.get(2));
        return new JuryTable(vote(s, ballots), plain, sharp, a, b);
    }

    @Test void theGhostJuryBreaksATie_andASuperFaithfulQuietlyCountsDouble() {
        JuryTable j = juryTable("random", Map.of("ghost_jury", Map.of()), 71);
        TruearenaState s = j.state();
        assertThat(s.phase).isEqualTo("GhostJury");
        assertThat(s.tieCandidates).containsExactlyInAnyOrder(j.a(), j.b());
        assertThat(view(s, j.superGhost())).containsEntry("ghostJuror", true);
        assertThat(view(s, j.a())).doesNotContainKey("ghostJuror");
        assertThat(broadcast(s).toString()).as("nobody is told who is Super").doesNotContain("rightVoters", "super");

        s = act(s, j.plainGhost(), "GHOST_VOTE", Map.of("target", j.b()));
        TruearenaState before = s;
        s = act(s, j.superGhost(), "GHOST_VOTE", Map.of("target", j.a()));
        List<GameEvent> verdict = events(before, s);
        assertThat(only(verdict, "GHOST_JURY_VERDICT").payload()).containsEntry("chosen", j.a());
        assertThat(s.alive).doesNotContain(j.a()).contains(j.b());
        assertThat(types(verdict)).doesNotContain("TIE_RESOLVED");
    }

    @Test void anUndecidedJuryHandsTheTieBackToTheModesOwnRule() {
        JuryTable j = juryTable("random", Map.of("ghost_jury", Map.of()), 72);
        TruearenaState before = j.state();
        TruearenaState s = elapse(before); // nobody voted before the clock
        List<GameEvent> after = events(before, s);
        assertThat(only(after, "GHOST_JURY_VERDICT").payload()).containsKey("undecided");
        assertThat(only(after, "TIE_RESOLVED").payload()).containsEntry("method", "random");
    }

    @Test void withNoGhostJuryTheTieGoesStraightToTheModesRule() {
        JuryTable j = juryTable("random", Map.of(), 73);
        assertThat(j.state().phase).isNotEqualTo("GhostJury");
        assertThat(j.state().alive).hasSize(4);
    }

    @Test void inClassicTheJurySitsOnlyAfterTheRevote() {
        JuryTable j = juryTable("revote", Map.of("ghost_jury", Map.of("afterRevote", true)), 74);
        TruearenaState s = j.state();
        assertThat(s.phase).as("the revote comes first").isEqualTo("Revote");
        List<String> others = s.alive.stream().filter(id -> !id.equals(j.a()) && !id.equals(j.b())).sorted().toList();
        s = act(s, others.get(0), "CAST_VOTE", Map.of("target", j.a()));
        s = act(s, others.get(1), "CAST_VOTE", Map.of("target", j.b()));
        s = elapse(s); // the rest abstain: still tied
        assertThat(s.phase).isEqualTo("GhostJury");
    }

    // ---------------------------------------------------------------- the Crowd's Hunch

    @Test void theCrowdIsSpectatorsAndFaithfulGhosts_andTheTableSeesItFromThreeVoices() {
        JuryTable j = juryTable("no_elimination", Map.of("crowd_hunch", Map.of()), 81);
        TruearenaState s = until(j.state(), "Night");
        s = until(murder(s, s.aliveFaithful().getFirst()), "RoundTable");
        String suspect = s.alive.stream().sorted().findFirst().orElseThrow();
        String player = s.alive.stream().filter(id -> !id.equals(suspect)).findFirst().orElseThrow();
        TruearenaState table = s;
        assertThatThrownBy(() -> act(table, player, "CROWD_VOTE", Map.of("target", suspect)))
                .as("players at the table can't").isInstanceOf(RuleViolation.class);
        String fallenTraitor = s.eliminatedLog.stream().filter(s::isTraitor).findFirst().orElseThrow();
        assertThatThrownBy(() -> act(table, fallenTraitor, "CROWD_VOTE", Map.of("target", suspect)))
                .as("nor can a Traitor who's out").isInstanceOf(RuleViolation.class);

        s = act(s, "spectator-1", "CROWD_VOTE", Map.of("target", suspect));
        s = act(s, j.plainGhost(), "CROWD_VOTE", Map.of("target", suspect));
        @SuppressWarnings("unchecked") Map<String, Object> hunch = (Map<String, Object>) broadcast(s).get("crowdHunch");
        assertThat(hunch).containsEntry("voters", 2).doesNotContainKey("suspect");
        String other = s.alive.stream().filter(id -> !id.equals(suspect)).findFirst().orElseThrow();
        s = act(s, j.superGhost(), "CROWD_VOTE", Map.of("target", other));
        @SuppressWarnings("unchecked") Map<String, Object> shown = (Map<String, Object>) broadcast(s).get("crowdHunch");
        // Two plain voices for the suspect against one Super voice (worth two): an even split.
        assertThat(shown).containsEntry("voters", 3).containsEntry("percent", 50).containsEntry("split", true);
        assertThat(view(s, j.plainGhost())).containsEntry("canCrowdVote", true).containsEntry("yourCrowdVote", suspect);

        s = until(vote(s, Map.of()), "Night");
        @SuppressWarnings("unchecked") Map<String, Object> fresh = (Map<String, Object>) broadcast(s).get("crowdHunch");
        assertThat(fresh).as("a new round, a new hunch").containsEntry("voters", 0);
    }

    // ---------------------------------------------------------------- secrecy

    @Test void noTwistSecretReachesAFaithfulOrTheBroadcast() {
        Map<String, Map<String, Object>> all = new LinkedHashMap<>();
        for (String id : List.of("poisoned_pie", "black_spot", "seer_lantern", "alibis", "recruiting", "crowd_hunch", "ghost_jury")) {
            all.put(id, Map.of());
        }
        TruearenaState s = until(start(classic(10, 3, "random", all), 10, 91), "Night");
        String t = traitors(s).getFirst();
        s = act(s, t, "BAKE_PIE", Map.of("filling", "poison"));
        s = act(s, t, "PLACE_SPOT", Map.of("target", faithful(s).getFirst()));
        String seer = s.seer;
        String plainFaithful = faithful(s).stream().filter(id -> !id.equals(seer)).findFirst().orElseThrow();
        for (Map<String, Object> view : List.of(view(s, plainFaithful), broadcast(s))) {
            assertThat(view).doesNotContainKeys("pieBakedTonight", "spotPending", "canRecruit", "recruitTargets",
                    "seer", "fellowTraitors", "yourNightTarget", "recruitingTonight");
            @SuppressWarnings("unchecked") Map<String, Object> pie = (Map<String, Object>) view.get("pie");
            assertThat(pie).doesNotContainKeys("filling", "poisoned").containsEntry("available", false);
        }
    }

    @Test void everyModeStillPlaysToAnEnd() {
        for (Presets.Mode mode : Presets.ALL) {
            for (long seed = 1; seed <= 25; seed++) {
                int players = mode.config().table().players();
                AutoPlay.Result r = AutoPlay.run(mode.config(), players, seed);
                assertThat(r.winningSide()).as("%s seed %d", mode.slug(), seed).isIn("traitors", "faithful");
            }
        }
    }
}
