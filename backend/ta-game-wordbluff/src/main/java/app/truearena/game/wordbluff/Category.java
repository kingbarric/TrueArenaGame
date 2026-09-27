package app.truearena.game.wordbluff;

import java.util.List;

/**
 * The 20 categories on the wheel. 19 are backed by a word list resource file
 * (see {@code src/main/resources/wordbank/<slug>.txt}, one word per line —
 * hand-authored for v1, not scraped; grow any category toward the eventual
 * 500-word target by just adding more lines, no code change needed).
 * {@code MIXED} is the 20th spot and has no file of its own — it draws from
 * the union of every other category at spin time (see {@link WordBank}).
 */
public enum Category {
    ANIMALS("animals", "Animals"),
    NATURE("nature", "Nature"),
    CURRENT_AFFAIRS("current_affairs", "Current Affairs"),
    MOVIES_TV("movies_tv", "Movies & TV"),
    MUSIC("music", "Music"),
    FOOD_DRINK("food_drink", "Food & Drink"),
    SPORTS("sports", "Sports"),
    OCCUPATIONS("occupations", "Occupations"),
    FAMOUS_FACES("famous_faces", "Famous Faces"),
    PLACES_LANDMARKS("places_landmarks", "Places & Landmarks"),
    TECHNOLOGY("technology", "Technology"),
    EMOTIONS_ACTIONS("emotions_actions", "Emotions & Actions"),
    FICTIONAL_CHARACTERS("fictional_characters", "Fictional Characters"),
    EVERYDAY_OBJECTS("everyday_objects", "Everyday Objects"),
    SCIENCE("science", "Science"),
    HISTORY("history", "History"),
    SCHOOL_EDUCATION("school_education", "School & Education"),
    TRAVEL_TRANSPORT("travel_transport", "Travel & Transport"),
    CLOTHING_FASHION("clothing_fashion", "Clothing & Fashion"),
    MIXED("mixed", "Mixed");

    public static final List<Category> ALL = List.of(values());
    public static final List<Category> WORD_FILE_BACKED = ALL.stream().filter(c -> c != MIXED).toList();

    private final String slug;
    private final String displayName;

    Category(String slug, String displayName) {
        this.slug = slug;
        this.displayName = displayName;
    }

    public String slug() {
        return slug;
    }

    public String displayName() {
        return displayName;
    }

    public static Category bySlug(String slug) {
        for (Category c : ALL) {
            if (c.slug.equals(slug)) {
                return c;
            }
        }
        throw new IllegalArgumentException("unknown category: " + slug);
    }
}
