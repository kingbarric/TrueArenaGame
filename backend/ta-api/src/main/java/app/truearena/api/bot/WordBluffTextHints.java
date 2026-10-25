package app.truearena.api.bot;

import app.truearena.game.wordbluff.Category;
import app.truearena.game.wordbluff.WordClues;

import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * The agents' offline clue book — two hand-written clues for every word in
 * the bank (see {@link WordClues}). Describing reads a word's own clues;
 * guessing compares the public clue text against the book, never the secret
 * answer.
 */
final class WordBluffTextHints {

    /** The word's clues, best first; empty if the book doesn't have it. */
    static List<String> clues(String word) {
        return WordClues.forWord(word);
    }

    static Optional<String> clue(String word) {
        return clues(word).stream().findFirst();
    }

    /** A guess from the clues said so far, from the words on the wheel's category ({@code null}: any). */
    static Optional<String> guess(String publicClue, String categoryName) {
        return guess(publicClue, categoryName, 2);
    }

    static Optional<String> guess(String publicClue, String categoryName, int minimumOverlap) {
        Category category = WordClues.categoryNamed(categoryName);
        Map<String, List<String>> book = WordClues.byCategory(category == null ? Category.MIXED : category);
        Set<String> words = tokens(publicClue);
        String best = null;
        int bestScore = minimumOverlap - 1;
        boolean tied = false;
        for (var entry : book.entrySet()) {
            int score = (int) tokens(String.join(" ", entry.getValue())).stream().filter(words::contains).count();
            if (score > bestScore) { best = entry.getKey(); bestScore = score; tied = false; }
            else if (score == bestScore) tied = true;
        }
        return tied ? Optional.empty() : Optional.ofNullable(best);
    }

    static Optional<String> guess(String publicClue) {
        return guess(publicClue, null);
    }

    private static Set<String> tokens(String text) {
        Set<String> stop = Set.of("this", "that", "with", "from", "have", "your", "they", "what", "where", "often",
                "someone", "something", "when", "into", "like", "them", "their", "used", "also", "very");
        return Arrays.stream(text.toLowerCase(java.util.Locale.ROOT).split("[^a-z]+"))
                .filter(w -> w.length() > 3 && !stop.contains(w)).collect(Collectors.toSet());
    }
    private WordBluffTextHints() {}
}
