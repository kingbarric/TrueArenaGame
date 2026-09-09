package app.truearena.api.game;

import app.truearena.api.support.CurrentUser;
import app.truearena.engine.GameConfig;
import app.truearena.game.truearena.ConfigValidator;
import app.truearena.game.truearena.TwistRegistry;
import app.truearena.persistence.GameConfigPresetRepository;
import app.truearena.persistence.GameConfigPresetRow;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/config")
@Tag(name = "config", description = "GameConfig presets, the twist catalog, and validation (docs/GAME_CONFIG.md).")
public class ConfigController {

    private final GameConfigPresetRepository presets;
    private final GameJson json;

    public ConfigController(GameConfigPresetRepository presets, GameJson json) {
        this.presets = presets;
        this.json = json;
    }

    public record PresetView(String id, String scope, String slug, String name, String tag,
                             String description, int catalogVersion, Object config) {
    }

    public record ValidationView(boolean ok, List<String> errors, List<String> warnings) {
    }

    @GetMapping("/presets")
    @Operation(summary = "Builtin modes plus the caller's saved custom games")
    public Flux<PresetView> presets() {
        Flux<GameConfigPresetRow> builtin = presets.findByScope("builtin");
        Flux<GameConfigPresetRow> mine = CurrentUser.id()
                .flatMapMany(uid -> presets.findByScopeAndOwnerUserId("user", uid));
        return Flux.concat(builtin, mine).map(this::toView);
    }

    @GetMapping("/twists")
    @Operation(summary = "The twist catalog for the current version")
    public List<TwistRegistry.Twist> twists() {
        return List.copyOf(TwistRegistry.all().values());
    }

    @PostMapping("/validate")
    @Operation(summary = "Validate a GameConfig against the current catalog")
    public Mono<ValidationView> validate(@RequestBody Map<String, Object> body) {
        GameConfig cfg = json.readConfig(body);
        ConfigValidator.Result r = ConfigValidator.validate(cfg);
        return Mono.just(new ValidationView(r.ok(), r.errors(), r.warnings()));
    }

    private PresetView toView(GameConfigPresetRow row) {
        // parse to a typed GameConfig so the response carries a clean object, not a JSON string
        Object cfg = row.configJson() == null ? null : json.readConfig(row.configJson());
        return new PresetView(String.valueOf(row.id()), row.scope(), row.slug(), row.name(), row.tag(),
                row.description(), row.catalogVersion(), cfg);
    }
}
