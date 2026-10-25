package app.truearena.api.bot;

import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.List;
import java.util.Random;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class TraitorsTableTalkTest {

    @Test
    void sixAgentsAtATableGetSixDifferentVoices() {
        List<String> agents = List.of("a1", "a2", "a3", "a4", "a5", "a6");
        Set<TraitorsTableTalk.Persona> voices = new HashSet<>();
        for (String agent : agents) voices.add(TraitorsTableTalk.Persona.of(agent, agents));
        assertThat(voices).hasSize(6);
    }

    @Test
    void eachVoiceOpensDifferentlyAndNamesNames() {
        Set<String> lines = new HashSet<>();
        for (TraitorsTableTalk.Persona persona : TraitorsTableTalk.Persona.values()) {
            String line = new TraitorsTableTalk(new Random(1)).open(persona, "Ada");
            assertThat(line).contains("Ada").doesNotContain("{");
            lines.add(line);
        }
        assertThat(lines).hasSize(TraitorsTableTalk.Persona.values().length);
    }

    @Test
    void anAgentDoesNotRepeatItselfUntilItHasUsedEveryLine() {
        TraitorsTableTalk talk = new TraitorsTableTalk(new Random(3));
        Set<String> said = new HashSet<>();
        for (int i = 0; i < 4; i++) said.add(talk.open(TraitorsTableTalk.Persona.JOKER, "Ada"));
        assertThat(said).hasSize(4);
    }

    @Test
    void repliesAnswerTheSpeakerAndDefendWhenAccused() {
        TraitorsTableTalk talk = new TraitorsTableTalk(new Random(5));
        String reply = talk.reply(TraitorsTableTalk.Persona.DETECTIVE, "Kofi", "Ada", false);
        assertThat(reply).contains("Kofi");
        String defence = talk.reply(TraitorsTableTalk.Persona.DETECTIVE, "Kofi", "Ada", true);
        assertThat(TraitorsTableTalk.Persona.DETECTIVE.defences.stream()
                .map(l -> l.replace("{speaker}", "Kofi").replace("{name}", "Ada"))).contains(defence);
    }

    @Test
    void suspicionMostlyFollowsWhoTheTableIsTalkingAbout() {
        TraitorsTableTalk talk = new TraitorsTableTalk(new Random(11));
        List<String> discussion = List.of("Ama: Chidi is lying", "Kofi: yes, Chidi again", "Esi: watch Chidi");
        int chidi = 0;
        for (int i = 0; i < 60; i++) if (talk.suspect(List.of("Ada", "Chidi", "Dayo"), discussion).equals("Chidi")) chidi++;
        assertThat(chidi).isGreaterThan(30);
    }
}
