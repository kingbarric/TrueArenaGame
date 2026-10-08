package app.truearena.api.slay;

import app.truearena.engine.slay.SlayRules.*;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.util.*;

@Component
public class SlayCatalog {
    public record Client(String id, String name, String brief, String themeId) {}

    public record Avatar(String body, String assetUrl, String rigVersion) {}

    public record Manifest(
            int version,
            boolean developmentAssets,
            List<Avatar> avatars,
            List<Item> items,
            List<Theme> themes,
            List<String> poses,
            List<String> backgrounds,
            List<String> skinTones,
            List<String> facePresets,
            List<Client> clients) {}

    private final Manifest manifest;

    public SlayCatalog(ObjectMapper mapper) throws Exception {
        try (var in = new ClassPathResource("slay/catalog.json").getInputStream()) {
            manifest = mapper.readValue(in, Manifest.class);
        }
    }

    public Manifest manifest() {
        return manifest;
    }

    public Map<String, Item> items() {
        Map<String, Item> items = new LinkedHashMap<>();
        manifest.items().forEach(i -> items.put(i.id(), i));
        return items;
    }

    public Theme theme(String id) {
        return manifest.themes().stream()
                .filter(t -> t.id().equals(id))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Unknown theme"));
    }
}
