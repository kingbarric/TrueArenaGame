package app.truearena.api.bot;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Pins the two properties that make agent table talk feel human rather than
 * like a chatbot: it is mostly quiet when nothing happens, and it never
 * repeats itself.
 */
class AgentBanterTest {

    /** Fraction of routine turns on which it speaks, over a long run. */
    private double routineChatterRate(int turns) {
        AgentBanter banter = new AgentBanter();
        int spoke = 0;
        for (int i = 0; i < turns; i++) {
            if (banter.shouldSpeak(false)) {
                spoke++;
                // speaking resets the quiet streak, same as a real accepted line
                banter.accept("line number " + i);
            }
        }
        return spoke / (double) turns;
    }

    @Test
    void staysMostlyQuietWhenNothingInterestingHappens() {
        double rate = routineChatterRate(4000);
        // The exact number doesn't matter; "usually says nothing" does. A
        // commentary track on every move is the failure mode being guarded.
        assertThat(rate)
                .as("routine-move chatter rate")
                .isLessThan(0.25)
                .isGreaterThan(0.01); // but not mute for an entire game either
    }

    @Test
    void speaksUpMuchMoreOftenWhenSomethingActuallyHappens() {
        AgentBanter notableRun = new AgentBanter();
        int spoke = 0;
        for (int i = 0; i < 4000; i++) {
            if (notableRun.shouldSpeak(true)) {
                spoke++;
                notableRun.accept("captured " + i);
            }
        }
        double notableRate = spoke / 4000.0;
        assertThat(notableRate).isGreaterThan(routineChatterRate(4000) * 2);
    }

    @Test
    void aLongSilenceNudgesButNeverForcesARoutineComment() {
        AgentBanter banter = new AgentBanter();
        // Never accept anything, so the quiet streak grows without bound.
        int spokeInLastStretch = 0;
        for (int i = 0; i < 500; i++) {
            if (banter.shouldSpeak(false)) {
                spokeInLastStretch++;
            }
        }
        // Even with a very long silence the odds stay well short of certain.
        assertThat(spokeInLastStretch / 500.0).isLessThan(0.35);
    }

    @Test
    void dropsAnExactRepeatEvenIfTheModelIgnoresTheBanList() {
        AgentBanter banter = new AgentBanter();
        assertThat(banter.accept("Nice one.")).isEqualTo("Nice one.");
        assertThat(banter.accept("nice one!")).isNull(); // same line, different casing/punctuation
    }

    @Test
    void cleansUpModelFormattingQuirks() {
        AgentBanter banter = new AgentBanter();
        assertThat(banter.accept("  \"Okay, that hurt.\"  ")).isEqualTo("Okay, that hurt.");
        assertThat(banter.accept("Ada: right, my turn")).isEqualTo("right, my turn");
    }

    @Test
    void refusesAnythingTooLongToBeTableTalk() {
        AgentBanter banter = new AgentBanter();
        assertThat(banter.accept("a".repeat(200))).isNull();
        assertThat(banter.accept("")).isNull();
        assertThat(banter.accept(null)).isNull();
    }

    @Test
    void remembersOnlyTheRecentLines() {
        AgentBanter banter = new AgentBanter();
        for (int i = 0; i < 20; i++) {
            banter.accept("line " + i);
        }
        assertThat(banter.recentLines()).hasSize(6);
        assertThat(banter.recentLines()).last().isEqualTo("line 19");
    }
}
