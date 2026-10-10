package app.truearena.game.wordbluff;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Hand-written clues for every word in the {@link WordBank}, two per word,
 * from {@code wordbank/clues/<slug>.txt} ({@code word | clue | clue}). What
 * a Cyber Agent says when it describes — and what it falls back on when no
 * model is answering. No clue says its word (checked by WordCluesTest).
 */
public final class WordClues {

    private static final Map<Category, Map<String, List<String>>> CACHE = new LinkedHashMap<>();

    /** The clues for {@code word}, best first; empty if it has none. */
    public static List<String> forWord(String word) {
        if (word == null) return List.of();
        String key = key(word);
        for (Category c : Category.WORD_FILE_BACKED) {
            List<String> clues = byCategory(c).get(key);
            if (clues != null) return clues;
        }
        return List.of();
    }

    /** Every word in {@code category} and its clues ({@code MIXED}: all of them). */
    public static synchronized Map<String, List<String>> byCategory(Category category) {
        if (category == Category.MIXED) {
            Map<String, List<String>> all = new LinkedHashMap<>();
            Category.WORD_FILE_BACKED.forEach(c -> byCategory(c).forEach(all::putIfAbsent));
            return all;
        }
        return CACHE.computeIfAbsent(category, WordClues::load);
    }

    /** The category a wheel label ("Food & Drink") or slug names, if any. */
    public static Category categoryNamed(String name) {
        if (name == null) return null;
        for (Category c : Category.ALL) {
            if (c.displayName().equalsIgnoreCase(name.strip()) || c.slug().equalsIgnoreCase(name.strip())) return c;
        }
        return null;
    }

    /**
     * Whether {@code text} gives {@code word} away by the table's own rule:
     * the word, with spaces, punctuation and accents squashed out, anywhere
     * in the squashed text (so "hot dog" is caught in "a hot-dog stand").
     */
    public static boolean saysWord(String text, String word) {
        if (text == null || word == null) return false;
        String w = WordBluffModule.normalizeText(word);
        return !w.isEmpty() && WordBluffModule.normalizeText(text).contains(w);
    }

    static String key(String word) {
        return word.strip().toLowerCase(Locale.ROOT);
    }

    private static Map<String, List<String>> load(Category category) {
        String resource = "/wordbank/clues/" + category.slug() + ".txt";
        try (InputStream in = WordClues.class.getResourceAsStream(resource)) {
            if (in == null) return Map.of();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
                Map<String, List<String>> out = new LinkedHashMap<>();
                reader.lines()
                        .map(String::strip)
                        .filter(line -> !line.isEmpty() && !line.startsWith("#"))
                        .forEach(line -> {
                            String[] parts = line.split("\\|");
                            if (parts.length < 2) return;
                            List<String> clues = Arrays.stream(parts).skip(1).map(String::strip)
                                    .filter(s -> !s.isEmpty()).toList();
                            out.putIfAbsent(key(parts[0]), clues);
                        });
                return Map.copyOf(out);
            }
        } catch (IOException e) {
            throw new UncheckedIOException("failed to read " + resource, e);
        }
    }

    private WordClues() {
    }
}
