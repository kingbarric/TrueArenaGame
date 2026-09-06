package app.truearena;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "app.truearena")
public class TrueArenaApplication {

    public static void main(String[] args) {
        SpringApplication.run(TrueArenaApplication.class, args);
    }
}
