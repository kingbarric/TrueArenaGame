package app.truearena.api.huudspace;

import app.truearena.api.slay.SlayCatalog;
import app.truearena.api.support.ApiExceptions;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import java.util.List;
import java.util.Map;

@Component
public class HuudAvatarCatalog {
    public record Avatar(String id, String name, String body, String skinTone, String hair, String thumbnailUrl) {}
    public record Outfit(String id, String name, Map<String,String> female, Map<String,String> male,
                         Map<String,String> colours, String swatch) {}
    public record Options(List<Avatar> avatars, List<Outfit> outfits) {}
    private final Options options;

    public HuudAvatarCatalog(ObjectMapper mapper, SlayCatalog slay) throws Exception {
        try (var input = new ClassPathResource("slay/huud-avatars.json").getInputStream()) {
            options = mapper.readValue(input, Options.class);
        }
        if (options.avatars().size() != 5 || options.outfits().size() != 10) throw new IllegalStateException("Huud avatar options are incomplete");
        for (var avatar : options.avatars()) {
            if (slay.manifest().avatars().stream().noneMatch(a -> avatar.id().equals(a.id()) && avatar.body().equals(a.body())))
                throw new IllegalStateException("Missing Huud avatar: " + avatar.id());
            for (var outfit : options.outfits()) {
                var items = avatar.body().equals("female") ? outfit.female() : outfit.male();
                for (var item : items.entrySet()) {
                    var source = slay.items().get(item.getValue());
                    if (source == null || !source.body().equals(avatar.body()) || !source.category().equals(item.getKey()))
                        throw new IllegalStateException("Invalid Huud outfit: " + outfit.id());
                }
            }
        }
    }
    public Options options() { return options; }
    public void validate(String avatar, String outfit) {
        if (options.avatars().stream().noneMatch(a -> a.id().equals(avatar))) throw ApiExceptions.badRequest("Choose one of the five Huud avatars");
        if (options.outfits().stream().noneMatch(o -> o.id().equals(outfit))) throw ApiExceptions.badRequest("Choose one of the ten outfits");
    }
}
