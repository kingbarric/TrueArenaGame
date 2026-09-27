package app.truearena.game.wordbluff;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Loads {@code wordbank/<slug>.txt} once per category and caches it. {@code
 * MIXED} isn't loaded from a file — {@link #wordsFor} returns the union of
 * every other category for it, computed once and cached the same way.
 */
public final class WordBank {

    private static final Map<Category, List<String>> CACHE = new LinkedHashMap<>();

    public static synchronized List<String> wordsFor(Category category) {
        List<String> cached = CACHE.get(category);
        if (cached != null) {
            return cached;
        }
        List<String> loaded = load(category);
        CACHE.put(category, loaded);
        return loaded;
    }

    private static List<String> load(Category category) {
        if (category == Category.MIXED) {
            return Category.WORD_FILE_BACKED.stream()
                    .flatMap(c -> wordsFor(c).stream())
                    .distinct()
                    .toList();
        }
        String resource = "/wordbank/" + category.slug() + ".txt";
        try (InputStream in = WordBank.class.getResourceAsStream(resource)) {
            if (in == null) {
                throw new IllegalStateException("missing word bank resource: " + resource);
            }
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
                return reader.lines()
                        .map(String::strip)
                        .filter(line -> !line.isEmpty())
                        .distinct()
                        .toList();
            }
        } catch (IOException e) {
            throw new UncheckedIOException("failed to read " + resource, e);
        }
    }

    private WordBank() {
    }
}
