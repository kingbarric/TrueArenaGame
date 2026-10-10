package app.truearena.api.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

import java.util.Arrays;

/**
 * Refuses to boot if {@code APP_ENV=production} but the {@code local} Spring
 * profile is also active — that profile turns on the OTP dev-bypass code
 * ({@code otp-dev-bypass-code: "000000"}, see application.yml) and registers
 * {@code DevGameController}'s unauthenticated {@code /api/v1/dev/simulate}.
 * There's no other signal in this repo that a deploy is "real prod" (no k8s,
 * no separate prod application.yml), so APP_ENV is the one this guard checks;
 * set it explicitly in infra/docker-compose.prod.yml.
 *
 * <p>The {@code test} profile (the test server, infra/docker-compose.test.yml) is
 * refused in production for the same reason: it turns on a shared sign-in code.
 */
@Component
public class EnvironmentGuard implements ApplicationRunner {

    private final Environment environment;
    private final String appEnv;

    public EnvironmentGuard(Environment environment, @Value("${APP_ENV:}") String appEnv) {
        this.environment = environment;
        this.appEnv = appEnv;
    }

    @Override
    public void run(ApplicationArguments args) {
        boolean isProduction = "production".equalsIgnoreCase(appEnv);
        var activeProfiles = Arrays.asList(environment.getActiveProfiles());
        if (isProduction && activeProfiles.contains("local")) {
            throw new IllegalStateException(
                    "APP_ENV=production but the 'local' Spring profile is active — this would expose "
                            + "the OTP dev-bypass code and /api/v1/dev/** unauthenticated. Refusing to start.");
        }
        if (isProduction && activeProfiles.contains("test")) {
            throw new IllegalStateException(
                    "APP_ENV=production but the 'test' Spring profile is active — this would turn on "
                            + "the test server's shared sign-in code. Refusing to start.");
        }
    }
}
