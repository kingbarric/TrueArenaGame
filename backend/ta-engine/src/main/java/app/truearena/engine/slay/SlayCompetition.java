package app.truearena.engine.slay;

import java.time.Instant;
import java.util.*;

/** Durable competition state; all deadlines are server timestamps, never device timers. */
public final class SlayCompetition {
    public String id, roomId, hostId, mode, themeId, status = "lobby", contestantBody = "male";
    public int seats = 2,
            stylingSeconds = 180,
            votingSeconds = 300,
            minVotes = 6,
            round = 1,
            revealIndex = 0;
    public double systemWeight = .35;
    public boolean requestedRanked = false, eligibleRating = false, communityUsed = false;
    public Instant deadline, startedAt;
    public List<Member> members = new ArrayList<>();
    public List<Entry> entries = new ArrayList<>();
    public List<String> eliminated = new ArrayList<>();
    public List<String> roundThemes = new ArrayList<>();
    public List<SlayRules.Comparison> comparisons = new ArrayList<>();
    public Set<String> voters = new HashSet<>();
    public Map<String, Boolean> judgements = new HashMap<>();

    public record Member(String userId, String role, String body) {}

    public static final class Entry {
        public String id, userId, lookId;
        public int round, placement = 0, slays = 0, passes = 0;
        public SlayRules.Score system;
        public double community = 50, finalScore;

        public Entry() {}

        public Entry(String id, String userId, String lookId, int round, SlayRules.Score score) {
            this.id = id;
            this.userId = userId;
            this.lookId = lookId;
            this.round = round;
            this.system = score;
        }
    }

    public List<Member> contestants() {
        return members.stream().filter(m -> m.role().equals("contestant")).toList();
    }

    public List<Member> active() {
        return contestants().stream().filter(m -> !eliminated.contains(m.userId())).toList();
    }

    public List<Member> judges() {
        return members.stream().filter(m -> m.role().equals("judge")).toList();
    }

    public List<Entry> currentEntries() {
        return entries.stream().filter(e -> e.round == round).toList();
    }

    public String currentTheme() {
        if (isElimination() && active().size() <= 2 && round > 1) return "red-carpet";
        return roundThemes.isEmpty()
                ? themeId
                : roundThemes.get(Math.min(round - 1, roundThemes.size() - 1));
    }

    public boolean isAsync() {
        return Set.of("daily", "weekly").contains(mode);
    }

    public boolean isElimination() {
        return "slay_or_pass".equals(mode);
    }

    public Entry revealed() {
        List<Entry> list = currentEntries();
        return revealIndex < list.size() ? list.get(revealIndex) : null;
    }

    public void start(Instant now) {
        if (mode == null || !Set.of("battle", "group", "slay_or_pass").contains(mode))
            fail("Unknown live competition mode");
        if (!"lobby".equals(status)) fail("Competition has already started");
        int count = contestants().size();
        if ("battle".equals(mode) && count != 2
                || "group".equals(mode) && (count < 4 || count > seats)
                || isElimination() && (count < 3 || judges().size() < 3 || judges().size() > 6))
            fail("Waiting for more players or judges");
        status = "styling";
        startedAt = now;
        deadline = now.plusSeconds(stylingSeconds);
    }

    public void submit(Entry entry, Instant now) {
        if (!"styling".equals(status) || !now.isBefore(deadline)) fail("Submissions are closed");
        if (active().stream().noneMatch(m -> m.userId().equals(entry.userId)))
            fail("You are not an active contestant");
        if (currentEntries().stream().anyMatch(e -> e.userId.equals(entry.userId)))
            fail("Your look is already submitted");
        entry.round = round;
        entries.add(entry);
        if (!isAsync() && currentEntries().size() == active().size()) openVoting(now);
    }

    public void openVoting(Instant now) {
        status = "voting";
        revealIndex = 0;
        deadline = now.plusSeconds(votingSeconds);
        if (currentEntries().size() < 2) finishRound(now);
    }

    public void judge(String user, String entry, boolean slay, Instant now) {
        if (!isElimination() || !"voting".equals(status) || !now.isBefore(deadline))
            fail("Judging is closed");
        if (judges().stream().noneMatch(m -> m.userId().equals(user)))
            fail("Only room judges can judge");
        if (currentEntries().size() == 2) fail("Choose between the final two looks");
        Entry target = revealed();
        if (target == null || !target.id.equals(entry)) fail("This look is not being revealed");
        String key = round + ":" + entry + ":" + user;
        if (judgements.containsKey(key)) fail("You already judged this look");
        judgements.put(key, slay);
        if (slay) target.slays++;
        else target.passes++;
        if (target.slays + target.passes == judges().size()) nextReveal(now);
    }

    public void finalVote(String user, String chosen, Instant now) {
        if (!isElimination()
                || !"voting".equals(status)
                || currentEntries().size() != 2
                || !now.isBefore(deadline)) fail("Final voting is closed");
        if (judges().stream().noneMatch(m -> m.userId().equals(user)))
            fail("Only room judges can judge");
        if (currentEntries().stream().noneMatch(e -> e.id.equals(chosen)))
            fail("Choose a finalist");
        String key = round + ":final:" + user;
        if (judgements.containsKey(key)) fail("You already chose a finalist");
        judgements.put(key, true);
        for (Entry e : currentEntries()) {
            if (e.id.equals(chosen)) e.slays++;
            else e.passes++;
        }
        if (currentEntries().get(0).slays + currentEntries().get(0).passes == judges().size())
            finishRound(now);
    }

    private void nextReveal(Instant now) {
        revealIndex++;
        if (revealIndex >= currentEntries().size()) finishRound(now);
        else deadline = now.plusSeconds(votingSeconds);
    }

    public void tick(Instant now) {
        if (deadline == null || now.isBefore(deadline)) return;
        switch (status) {
            case "styling" -> openVoting(now);
            case "voting" -> {
                if (isElimination()) nextReveal(now);
                else finishRound(now);
            }
            case "round_result" -> {
                round++;
                status = "styling";
                revealIndex = 0;
                comparisons.clear();
                voters.clear();
                deadline = now.plusSeconds(stylingSeconds);
            }
            case "lobby" -> {
                status = "cancelled";
                deadline = null;
            }
            default -> {}
        }
    }

    public void finishRound(Instant now) {
        List<Entry> current = new ArrayList<>(currentEntries());
        Map<String, Double> community =
                SlayRules.community(current.stream().map(e -> e.id).toList(), comparisons);
        Map<String, Long> exposure = new HashMap<>();
        comparisons.forEach(
                v -> {
                    exposure.merge(v.a(), 1L, Long::sum);
                    exposure.merge(v.b(), 1L, Long::sum);
                });
        int minExposure = isElimination() ? 3 : minVotes;
        boolean enough =
                current.size() >= 2
                        && current.stream()
                                .allMatch(
                                        e ->
                                                isElimination()
                                                        ? e.slays + e.passes >= minExposure
                                                        : exposure.getOrDefault(e.id, 0L)
                                                                >= minExposure);
        communityUsed = enough;
        eligibleRating =
                (round == 1 ? true : eligibleRating) && enough && requestedRanked && !isAsync();
        for (Entry e : current) {
            e.community =
                    isElimination()
                            ? SlayRules.round(
                                    e.slays + e.passes == 0
                                            ? 50
                                            : 100.0 * e.slays / (e.slays + e.passes))
                            : community.getOrDefault(e.id, 50.0);
            e.finalScore =
                    SlayRules.round(
                            enough
                                    ? systemWeight * e.system.overall()
                                            + (1 - systemWeight) * e.community
                                    : e.system.overall());
        }
        current.sort(
                Comparator.<Entry>comparingDouble(e -> e.finalScore)
                        .reversed()
                        .thenComparing(
                                Comparator.<Entry>comparingDouble(e -> e.system.overall())
                                        .reversed())
                        .thenComparing(e -> e.id));
        List<String> missing =
                active().stream()
                        .map(Member::userId)
                        .filter(id -> current.stream().noneMatch(e -> e.userId.equals(id)))
                        .toList();
        if (isElimination()) {
            eliminated.addAll(missing);
            if (current.size() > 2) {
                Entry loser = current.get(current.size() - 1);
                eliminated.add(loser.userId);
                loser.placement = active().size() + 1;
                status = "round_result";
                deadline = now.plusSeconds(8);
                return;
            }
        }
        int position = 0;
        double prev = Double.NaN;
        int place = 0;
        for (Entry e : current) {
            position++;
            if (e.finalScore != prev) {
                place = position;
                prev = e.finalScore;
            }
            e.placement = place;
        }
        // Elimination order becomes the group finishing order; judges never get competitor
        // rewards/rating.
        if (isElimination())
            for (int i = 0; i < eliminated.size(); i++) {
                String user = eliminated.get(i);
                int p = contestants().size() - i;
                entries.stream()
                        .filter(e -> e.userId.equals(user))
                        .max(Comparator.comparingInt(e -> e.round))
                        .ifPresent(e -> e.placement = p);
            }
        status = current.isEmpty() ? "cancelled" : "results";
        deadline = null;
    }

    private static void fail(String message) {
        throw new IllegalArgumentException(message);
    }
}
