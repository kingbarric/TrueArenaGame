package app.truearena.app;

import app.truearena.api.bot.ScanEngine;
import org.springframework.boot.actuate.info.InfoContributor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class ScanInfoConfig {
    @Bean public InfoContributor scanInfo(ScanEngine engine) { return builder -> builder.withDetail("scan", engine.status()); }
}
