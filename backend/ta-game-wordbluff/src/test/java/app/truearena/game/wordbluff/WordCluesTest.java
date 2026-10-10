package app.truearena.game.wordbluff;

import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class WordCluesTest {

    /** Short everyday words that happen to sit inside answers ("a" in "ant"). */
    private static final Set<String> COMMON = Set.of("that", "with", "your", "from", "this", "they", "them",
            "have", "when", "what", "into", "over", "make", "made", "like", "where", "after", "before", "under",
            "they're", "it's", "you're", "here", "there", "then", "than", "time", "each", "very", "more", "most",
            "less", "only", "also", "some", "many", "much", "well", "just", "back", "down", "away", "long");

    @Test
    void everyWordHasTwoCluesThatNeverSayIt() {
        List<String> problems = new ArrayList<>();
        for (Category c : Category.WORD_FILE_BACKED) {
            for (String word : WordBank.wordsFor(c)) {
                List<String> clues = WordClues.byCategory(c).get(WordClues.key(word));
                if (clues == null || clues.size() < 2) {
                    problems.add(c.slug() + ": no clues for '" + word + "'");
                    continue;
                }
                for (String clue : clues) {
                    String why = givesItAway(word, clue);
                    if (why != null) problems.add(c.slug() + ": '" + word + "' — " + why + " — " + clue);
                }
            }
        }
        assertThat(problems).isEmpty();
    }

    @Test
    void lookupFindsWordsByAnyCaseAndCategoriesByLabel() {
        assertThat(WordClues.forWord("Elephant")).hasSizeGreaterThanOrEqualTo(2);
        assertThat(WordClues.forWord("no such word")).isEmpty();
        assertThat(WordClues.categoryNamed("Food & Drink")).isEqualTo(Category.FOOD_DRINK);
        assertThat(WordClues.byCategory(Category.MIXED)).containsKey("elephant");
    }

    @Test
    void guessesForgiveArticlesAndPlurals() {
        assertThat(WordBluffModule.guessMatches("An Elephant", "elephant")).isTrue();
        assertThat(WordBluffModule.guessMatches("elephants", "elephant")).isTrue();
        assertThat(WordBluffModule.guessMatches("butterflies", "butterfly")).isTrue();
        assertThat(WordBluffModule.guessMatches("scissor", "scissors")).isTrue();
        assertThat(WordBluffModule.guessMatches("a cappella", "a cappella")).isTrue();
        assertThat(WordBluffModule.guessMatches("Hot-dog", "hot dog")).isTrue();
        assertThat(WordBluffModule.guessMatches("lion", "elephant")).isFalse();
        assertThat(WordBluffModule.guessMatches("", "elephant")).isFalse();
    }

    /** Null when the clue is fair; otherwise what's wrong with it. */
    private static String givesItAway(String word, String clue) {
        // The server's own rule: the word, squashed, anywhere in the squashed clue.
        if (WordBluffModule.normalizeText(clue).contains(WordBluffModule.normalizeText(word))) {
            return "server would reject it";
        }
        List<String> answer = tokens(word);
        for (String t : tokens(clue)) {
            if (COMMON.contains(t)) continue;
            for (String a : answer) {
                // "fish" in "fisherman", or "farmer" sharing "farm".
                if (t.length() >= 4 && a.contains(t)) return "says part of it ('" + t + "')";
                if (a.length() >= 3 && t.contains(a)) return "says part of it ('" + a + "')";
            }
        }
        return null;
    }

    private static List<String> tokens(String text) {
        return Arrays.stream(text.toLowerCase(Locale.ROOT).split("[^a-z0-9']+"))
                .map(s -> s.replaceAll("^'+|'+$", "").replaceAll("'s$", ""))
                .filter(s -> !s.isEmpty())
                .toList();
    }
}
