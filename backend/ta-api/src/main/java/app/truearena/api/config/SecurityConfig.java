package app.truearena.api.config;

import app.truearena.api.auth.JwtService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.config.web.server.SecurityWebFiltersOrder;
import org.springframework.security.config.web.server.ServerHttpSecurity;
import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import org.springframework.security.web.server.SecurityWebFilterChain;
import org.springframework.web.server.WebFilter;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.UUID;

@Configuration
public class SecurityConfig {

    private static final String[] PUBLIC = {
            "/actuator/**",
            "/v3/api-docs/**", "/v3/api-docs.yaml",
            "/swagger-ui/**", "/swagger-ui.html", "/webjars/**",
            "/api/v1/auth/**",
            "/api/v1/config/twists", "/api/v1/config/validate",
            "/api/v1/dev/**",
    };

    @Bean
    SecurityWebFilterChain securityWebFilterChain(ServerHttpSecurity http, JwtService jwt) {
        return http
                .csrf(ServerHttpSecurity.CsrfSpec::disable)
                .httpBasic(ServerHttpSecurity.HttpBasicSpec::disable)
                .formLogin(ServerHttpSecurity.FormLoginSpec::disable)
                .logout(ServerHttpSecurity.LogoutSpec::disable)
                .authorizeExchange(ex -> ex
                        .pathMatchers(PUBLIC).permitAll()
                        .pathMatchers("/api/**").authenticated()
                        .anyExchange().permitAll())
                .addFilterAt(bearerFilter(jwt), SecurityWebFiltersOrder.AUTHENTICATION)
                .exceptionHandling(e -> e.authenticationEntryPoint((exchange, ex) -> {
                    exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
                    return exchange.getResponse().setComplete();
                }))
                .build();
    }

    private WebFilter bearerFilter(JwtService jwt) {
        return (exchange, chain) -> {
            String header = exchange.getRequest().getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
            if (header == null || !header.startsWith("Bearer ")) {
                return chain.filter(exchange);
            }
            try {
                UUID userId = jwt.parseAccess(header.substring(7));
                var auth = new UsernamePasswordAuthenticationToken(userId.toString(), null, List.of());
                return chain.filter(exchange)
                        .contextWrite(ReactiveSecurityContextHolder.withAuthentication(auth));
            } catch (RuntimeException invalid) {
                return chain.filter(exchange);
            }
        };
    }
}
