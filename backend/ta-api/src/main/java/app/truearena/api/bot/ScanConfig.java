package app.truearena.api.bot;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class ScanConfig {
    @Bean(destroyMethod = "close")
    public ScanEngine scanEngine(@Value("${bots.draughts.scan.enabled:true}") boolean enabled,
            @Value("${bots.draughts.scan.path:scan}") String path,
            @Value("${bots.draughts.scan.directory:.}") String directory,
            @Value("${bots.draughts.scan.processes:2}") int processes,
            @Value("${bots.draughts.scan.tt-size:20}") int ttSize,
            @Value("${bots.draughts.scan.max-think-ms:1200}") long maxThinkMs) {
        var engine = new ScanEngine(new ScanEngine.Settings(enabled, path, directory, processes, ttSize, maxThinkMs));
        engine.warmUp(); return engine;
    }
}
