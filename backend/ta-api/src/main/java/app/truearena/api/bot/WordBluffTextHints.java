package app.truearena.api.bot;

import java.util.Arrays;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

/** Small offline safety net. Guessing compares public clue words, never the secret answer. */
final class WordBluffTextHints {
    private static final Map<String, String> CLUES = Map.ofEntries(
            Map.entry("elephant", "A huge grey animal with a long trunk and tusks."),
            Map.entry("lion", "A large cat with a mane that roars."),
            Map.entry("tiger", "A large striped cat that hunts in the jungle."),
            Map.entry("giraffe", "A spotted animal with a very long neck."),
            Map.entry("penguin", "A black and white bird that waddles on ice and cannot fly."),
            Map.entry("kangaroo", "An Australian animal that hops and carries its baby in a pouch."),
            Map.entry("dolphin", "A clever sea mammal that jumps above the water."),
            Map.entry("snake", "A long reptile with no legs that slithers."),
            Map.entry("eagle", "A large bird of prey with sharp talons."),
            Map.entry("octopus", "A sea creature with eight arms."),
            Map.entry("crocodile", "A large reptile with sharp teeth that waits near rivers."),
            Map.entry("zebra", "An African animal with black and white stripes."),
            Map.entry("dog", "A loyal pet that barks and wags its tail."),
            Map.entry("cat", "A pet that purrs and chases mice."),
            Map.entry("umbrella", "You hold this over your head to stay dry in the rain."),
            Map.entry("chair", "A seat with a back and usually four legs."),
            Map.entry("table", "Furniture with a flat surface where you eat meals."),
            Map.entry("mirror", "You look into this to see your reflection."),
            Map.entry("clock", "An object with hands that tells the time."),
            Map.entry("toothbrush", "You use this with paste to clean your teeth."),
            Map.entry("scissors", "Two sharp blades you use to cut paper."),
            Map.entry("key", "A small metal object used to unlock a door."),
            Map.entry("pencil", "You write with this and can erase its marks."),
            Map.entry("bicycle", "You pedal this vehicle with two wheels."),
            Map.entry("airplane", "A winged vehicle that carries passengers through the sky."),
            Map.entry("train", "A vehicle with carriages that travels on rails."),
            Map.entry("boat", "A vessel that carries people across water."),
            Map.entry("doctor", "Someone who treats sick people in a hospital."),
            Map.entry("teacher", "Someone who helps pupils learn in a classroom."),
            Map.entry("chef", "Someone who cooks meals in a restaurant kitchen."),
            Map.entry("firefighter", "Someone who rescues people and puts out burning buildings."),
            Map.entry("pizza", "A round baked meal with tomato sauce and melted cheese."),
            Map.entry("banana", "A curved yellow fruit that you peel before eating."),
            Map.entry("apple", "A crunchy round fruit, often red or green."),
            Map.entry("coffee", "A hot dark drink made from roasted beans."),
            Map.entry("volcano", "A mountain that erupts with hot lava."),
            Map.entry("rainbow", "An arc of different colours seen after rain."),
            Map.entry("snow", "Cold white flakes that fall from the sky in winter."),
            Map.entry("moon", "The bright natural satellite visible in the night sky."),
            Map.entry("sun", "The star that gives our planet light and warmth.")
    );

    static Optional<String> clue(String word) {
        if (word == null) return Optional.empty();
        return Optional.ofNullable(CLUES.get(word.toLowerCase(java.util.Locale.ROOT)));
    }

    static Optional<String> guess(String publicClue) {
        Set<String> words = tokens(publicClue);
        String best = null;
        int bestScore = 1;
        boolean tied = false;
        for (var entry : CLUES.entrySet()) {
            int score = (int) tokens(entry.getValue()).stream().filter(words::contains).count();
            if (score > bestScore) { best = entry.getKey(); bestScore = score; tied = false; }
            else if (score == bestScore) tied = true;
        }
        return tied ? Optional.empty() : Optional.ofNullable(best);
    }

    private static Set<String> tokens(String text) {
        Set<String> stop = Set.of("this", "that", "with", "from", "have", "your", "they", "what", "where", "often", "someone");
        return Arrays.stream(text.toLowerCase(java.util.Locale.ROOT).split("[^a-z]+"))
                .filter(w -> w.length() > 3 && !stop.contains(w)).collect(Collectors.toSet());
    }
    private WordBluffTextHints() {}
}
