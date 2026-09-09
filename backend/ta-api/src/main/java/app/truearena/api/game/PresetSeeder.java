package app.truearena.api.game;

import app.truearena.game.truearena.Presets;
import app.truearena.persistence.GameConfigPresetRepository;
import app.truearena.persistence.GameConfigPresetRow;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;

/**
 * Rewrites the {@code scope='builtin'} preset rows from {@link Presets} on every boot,
 * so the shipped modes always match this build. Group/user presets are untouched.
 */
@Component
public class PresetSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(PresetSeeder.class);

    private final GameConfigPresetRepository repo;
    private final GameJson json;

    public PresetSeeder(GameConfigPresetRepository repo, GameJson json) {
        this.repo = repo;
        this.json = json;
    }

    @Override
    public void run(ApplicationArguments args) {
        long n = repo.deleteByScope("builtin")
                .thenMany(Flux.fromIterable(Presets.ALL).flatMap(mode ->
                        repo.save(GameConfigPresetRow.builtin(
                                mode.slug(), mode.name(), mode.tag(), mode.description(),
                                json.write(mode.config()), mode.config().catalogVersion()))))
                .count()
                .block();
        log.info("seeded {} builtin game-config presets", n);
    }
}
