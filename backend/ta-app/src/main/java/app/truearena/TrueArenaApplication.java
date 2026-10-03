package app.truearena;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication(scanBasePackages = "app.truearena")
@EnableScheduling
public class TrueArenaApplication {

    public static void main(String[] args) {
        SpringApplication.run(TrueArenaApplication.class, args);
    }
}
