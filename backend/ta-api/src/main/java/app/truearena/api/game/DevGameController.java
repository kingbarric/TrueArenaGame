package app.truearena.api.game;

import app.truearena.engine.GameConfig;
import app.truearena.game.truearena.AutoPlay;
import app.truearena.game.truearena.ConfigValidator;
import app.truearena.game.truearena.Presets;
import app.truearena.api.support.ApiExceptions;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Local-only. Runs a full deterministic game from a config (a preset slug or an inline
 * GameConfig) so the engine is exercisable over plain HTTP before the WebSocket layer exists.
 */
@RestController
@RequestMapping("/api/v1/dev")
@Profile("local")
@Tag(name = "dev", description = "Local-only helpers")
public class DevGameController {

    private final GameJson json;

    public DevGameController(GameJson json) {
        this.json = json;
    }

    public record SimulateRequest(String preset, Map<String, Object> config, Integer players, Long seed) {
    }

    @PostMapping("/simulate")
    @Operation(summary = "Auto-play a full game and return the winning side, the public event log, and the final roles")
    public Mono<AutoPlay.Result> simulate(@RequestBody SimulateRequest req) {
        GameConfig cfg;
        if (req.config() != null) {
            cfg = json.readConfig(req.config());
        } else {
            String slug = req.preset() == null ? "classic_conspiracy" : req.preset();
            Presets.Mode mode = Presets.bySlug(slug);
            if (mode == null) {
                throw ApiExceptions.badRequest("unknown preset '" + slug + "'");
            }
            cfg = mode.config();
        }

        ConfigValidator.Result v = ConfigValidator.validate(cfg);
        if (!v.ok()) {
            throw ApiExceptions.badRequest("invalid config: " + String.join("; ", v.errors()));
        }

        int players = req.players() != null ? req.players() : cfg.table().players();
        long seed = req.seed() != null ? req.seed() : ThreadLocalRandom.current().nextLong();
        return Mono.just(AutoPlay.run(cfg, players, seed));
    }
}
