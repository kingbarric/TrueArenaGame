package app.truearena.api.admin;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.web.server.ServerWebExchange;

/**
 * Gates every {@code /api/v1/admin/**} request behind a static shared secret, checked
 * against the {@code X-Admin-Key} header. Deliberately not part of the JWT auth system
 * used everywhere else — there's no admin-role concept in the user model, and this
 * surface is only ever called from the /notvisible/analytics page, never the app.
 * With no key configured (the dev default), every admin request is refused rather
 * than silently left open.
 */
@Component
public class AdminKeyFilter implements WebFilter {

    private final String adminKey;

    public AdminKeyFilter(@Value("${truearena.admin.api-key:}") String adminKey) {
        this.adminKey = adminKey;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String path = exchange.getRequest().getURI().getPath();
        if (!path.startsWith("/api/v1/admin/")) {
            return chain.filter(exchange);
        }
        String provided = exchange.getRequest().getHeaders().getFirst("X-Admin-Key");
        if (adminKey.isBlank() || provided == null || !constantTimeEquals(adminKey, provided)) {
            exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
            return exchange.getResponse().setComplete();
        }
        return chain.filter(exchange);
    }

    private static boolean constantTimeEquals(String a, String b) {
        return MessageDigest.isEqual(a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
    }
}
