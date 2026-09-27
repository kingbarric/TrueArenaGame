package app.truearena.api.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.mock.env.MockEnvironment;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.assertThatCode;

class EnvironmentGuardTest {

    private static final DefaultApplicationArguments NO_ARGS = new DefaultApplicationArguments();

    @Test
    void refusesToStart_whenProductionAndLocalProfileBothActive() {
        MockEnvironment env = new MockEnvironment();
        env.setActiveProfiles("local");
        EnvironmentGuard guard = new EnvironmentGuard(env, "production");

        assertThatThrownBy(() -> guard.run(NO_ARGS)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void startsFine_whenProductionWithNoLocalProfile() {
        MockEnvironment env = new MockEnvironment();
        EnvironmentGuard guard = new EnvironmentGuard(env, "production");

        assertThatCode(() -> guard.run(NO_ARGS)).doesNotThrowAnyException();
    }

    @Test
    void startsFine_whenLocalProfileActiveButAppEnvNotProduction() {
        MockEnvironment env = new MockEnvironment();
        env.setActiveProfiles("local");
        EnvironmentGuard guard = new EnvironmentGuard(env, "");

        assertThatCode(() -> guard.run(NO_ARGS)).doesNotThrowAnyException();
    }
}
