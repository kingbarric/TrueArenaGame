package app.truearena.api.bot;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Random;
import java.util.Set;

/**
 * What a Cyber Agent says at a Traitors table when no model is there to write
 * it — and the voice the model is asked to keep when one is. Every agent at a
 * table gets its own personality, so four agents never say the same thing:
 * one is a blunt sceptic, another jokes, another lays out the votes. Lines
 * name real players, answer the person who spoke, and never repeat what this
 * agent already said.
 *
 * <p>Nothing here knows a hidden role it shouldn't: a Traitor agent just
 * steers suspicion away from its own side, which is what a Traitor would do.
 */
final class TraitorsTableTalk {

    enum Persona {
        SCEPTIC("blunt and suspicious — questions everyone, trusts nobody easily",
                List.of("{name}, you've been very quiet. What are you hiding?",
                        "I'm not buying it. {name} has dodged every question so far.",
                        "Before anyone gets comfy — {name}, where do you stand?",
                        "Something about {name} doesn't add up for me."),
                List.of("Convenient, {speaker}. Why point that way now?",
                        "{speaker}, that's a nice story. Prove it.",
                        "Hold on, {speaker} — why so sure? That's what a Traitor would say.",
                        "I hear you, {speaker}, but {name} still bothers me more."),
                List.of("Me? Come on, {speaker}, look at {name} instead.",
                        "{speaker}, accusing me is the easiest move on the board. Try harder.",
                        "Nice try, {speaker}. I've been asking the hard questions all game.")),
        JOKER("playful and teasing — cracks a joke, but still makes a point",
                List.of("Okay, who had garlic for dinner? Because {name} looks guilty.",
                        "Not saying it's {name}… but it's probably {name}.",
                        "I came for the vibes and {name}'s vibes are off tonight.",
                        "Round table rule: whoever laughs last is the Traitor. {name}, smile for me."),
                List.of("{speaker}, that's the most Traitor thing I've heard all day.",
                        "Ha! {speaker}, you sound like you rehearsed that.",
                        "Love the energy, {speaker}, but my money's on {name}.",
                        "{speaker} said it with a straight face. Respect. Still suspicious."),
                List.of("Me? {speaker}, I can't even keep a secret about pizza.",
                        "Wow, {speaker}, throwing me under the bus? Rude. Look at {name}.",
                        "If I were a Traitor, {speaker}, would I really be this charming?")),
        DETECTIVE("methodical — talks about votes, timing and who defended whom",
                List.of("Look at last round's votes — {name} jumped on the pile very late.",
                        "Pattern I noticed: every time {name} talks, suspicion moves somewhere else.",
                        "{name} defended the last person banished. Worth remembering.",
                        "Let's go through it calmly. {name} has changed their story once already."),
                List.of("{speaker}, that matches what I saw — but check {name}'s vote too.",
                        "Interesting, {speaker}. Who were you voting for last round?",
                        "{speaker}, timing matters. Why bring that up only now?",
                        "Noted, {speaker}. My evidence still points at {name}."),
                List.of("{speaker}, check my votes. They've been consistent from the start.",
                        "Fair to ask, {speaker}, but my record points at {name}, not me.",
                        "I'd rather be questioned than ignored, {speaker}. Ask me anything.")),
        PEACEMAKER("calm and fair — wants everyone heard before anyone is banished",
                List.of("Let's hear from everyone before we vote. {name}, what do you think?",
                        "No rush, friends. {name}, you haven't said much — your thoughts?",
                        "We banished a Faithful last time. Let's be careful. {name}?",
                        "Can we each say who we trust? I'll start: I'm unsure about {name}."),
                List.of("That's fair, {speaker}. Let's give {name} a chance to answer.",
                        "{speaker}, I hear you. Let's not rush it though.",
                        "Good point, {speaker}. Does anyone else feel that way about {name}?",
                        "{speaker}, I'd like to hear {name} explain first."),
                List.of("I understand the worry, {speaker}. Ask me anything — I'm Faithful.",
                        "{speaker}, I get it, but let's not banish on a feeling.",
                        "Happy to explain myself, {speaker}. I've just been listening.")),
        HOTHEAD("dramatic and fiery — takes things personally and says so",
                List.of("I KNOW it's {name}. I can feel it in my bones.",
                        "{name}, look me in the eye and say you're Faithful.",
                        "Enough talking! It's {name} and we all know it.",
                        "I swear if we don't banish {name} tonight I'm flipping this table."),
                List.of("{speaker}, ARE YOU SERIOUS right now?",
                        "Oh please, {speaker}! Open your eyes — it's {name}!",
                        "{speaker}, I can't believe you're falling for this.",
                        "Yes, {speaker}! Finally someone sees it!"),
                List.of("ME?! {speaker}, how dare you. I've been Faithful from day one!",
                        "{speaker}, you're pointing at me because you're scared. Admit it.",
                        "Unbelievable, {speaker}. Watch {name} smile while you accuse me.")),
        QUIET("reserved — says little, but sharp when they do",
                List.of("Just watching {name}. That's all.",
                        "{name}. Something's off.",
                        "I've been listening. {name} talks a lot and says nothing.",
                        "One name from me: {name}."),
                List.of("Hm. {speaker} might be right.",
                        "Not convinced, {speaker}.",
                        "{speaker}… interesting. Still thinking {name}.",
                        "Agreed, {speaker}."),
                List.of("Wrong person, {speaker}.",
                        "I'm Faithful, {speaker}. Look at {name}.",
                        "Quiet isn't guilty, {speaker}."));

        final String style;
        final List<String> openers, replies, defences;

        Persona(String style, List<String> openers, List<String> replies, List<String> defences) {
            this.style = style;
            this.openers = openers;
            this.replies = replies;
            this.defences = defences;
        }

        /**
         * Distinct for the first six agents at a table: their place among its
         * agents picks the voice, turned by an amount the whole table shares
         * so different tables meet different voices.
         */
        static Persona of(String self, Collection<String> agents) {
            List<String> sorted = new ArrayList<>(new HashSet<>(agents));
            if (!sorted.contains(self)) sorted.add(self);
            sorted.sort(String::compareTo);
            int turn = Math.floorMod(String.join(",", sorted).hashCode(), values().length);
            return values()[(sorted.indexOf(self) + turn) % values().length];
        }
    }

    private static final List<String> NIGHT = List.of(
            "I say {name} tonight — they're getting too close.",
            "{name} has been asking too many questions. Let's take them.",
            "Let's go for {name}. Nobody will suspect us.",
            "My vote's {name}. Quick and quiet.",
            "{name} trusts us. That makes them the safest pick.",
            "What about {name}? They've been leading the table.");

    private final Random random;
    private final Set<String> said = new HashSet<>();

    TraitorsTableTalk(Random random) {
        this.random = random;
    }

    /** Opening the round table: pick someone to put a question to. */
    String open(Persona persona, String suspect) {
        return pick(persona.openers, Map.of("name", suspect));
    }

    /** Answering what {@code speaker} said; {@code accused} when they were talking about this agent. */
    String reply(Persona persona, String speaker, String suspect, boolean accused) {
        return pick(accused ? persona.defences : persona.replies, Map.of("speaker", speaker, "name", suspect));
    }

    /** At night, to fellow Traitors: who to take. */
    String night(String target) {
        return pick(NIGHT, Map.of("name", target));
    }

    /**
     * Who to point at: someone the table is already talking about, else
     * anyone. Never this agent — and a Traitor never points at its own side.
     */
    String suspect(List<String> candidates, List<String> discussion) {
        if (candidates.isEmpty()) return "someone";
        String best = null;
        int most = 0;
        String talk = String.join(" ", discussion).toLowerCase(Locale.ROOT);
        for (String name : candidates) {
            int count = countOf(talk, name.toLowerCase(Locale.ROOT));
            if (count > most) {
                most = count;
                best = name;
            }
        }
        // Mostly follow the table's suspicion, sometimes go your own way.
        return best != null && random.nextInt(3) > 0 ? best : candidates.get(random.nextInt(candidates.size()));
    }

    private String pick(List<String> pool, Map<String, String> fill) {
        List<String> fresh = new ArrayList<>();
        for (String line : pool) {
            if (!said.contains(fill(line, fill))) fresh.add(line);
        }
        List<String> from = fresh.isEmpty() ? pool : fresh;
        String line = fill(from.get(random.nextInt(from.size())), fill);
        said.add(line);
        return line;
    }

    private static String fill(String line, Map<String, String> fill) {
        String out = line;
        for (Map.Entry<String, String> e : fill.entrySet()) out = out.replace("{" + e.getKey() + "}", e.getValue());
        return out;
    }

    private static int countOf(String text, String word) {
        if (word.isBlank()) return 0;
        int count = 0;
        for (int i = text.indexOf(word); i >= 0; i = text.indexOf(word, i + word.length())) count++;
        return count;
    }
}
