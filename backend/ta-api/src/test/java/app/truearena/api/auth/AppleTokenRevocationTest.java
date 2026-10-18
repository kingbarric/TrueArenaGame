package app.truearena.api.auth;

import com.sun.net.httpserver.HttpServer;
import io.jsonwebtoken.Jwts;
import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.server.ResponseStatusException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.security.KeyPairGenerator;
import java.security.interfaces.ECPublicKey;
import java.time.Duration;
import java.util.Base64;
import java.util.concurrent.atomic.AtomicReference;
import static org.assertj.core.api.Assertions.*;

class AppleTokenRevocationTest {
    @Test void signsCorrectAppleClientSecretAndUsesRefreshTokenForRevocation() throws Exception {
        var gen=KeyPairGenerator.getInstance("EC"); gen.initialize(256); var pair=gen.generateKeyPair();
        String pem="-----BEGIN PRIVATE KEY-----\n"+Base64.getEncoder().encodeToString(pair.getPrivate().getEncoded())
                +"\n-----END PRIVATE KEY-----";
        String encoded=Base64.getEncoder().encodeToString(pem.getBytes(StandardCharsets.US_ASCII));
        var grant=new AtomicReference<String>(); var revoke=new AtomicReference<String>();
        var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        server.createContext("/auth/token",exchange -> {
            grant.set(new String(exchange.getRequestBody().readAllBytes(),StandardCharsets.UTF_8));
            String id="header."+Base64.getUrlEncoder().withoutPadding().encodeToString(
                    "{\"sub\":\"apple-player\"}".getBytes(StandardCharsets.UTF_8))+".signature";
            byte[] body=("{\"id_token\":\""+id+"\",\"refresh_token\":\"test-refresh\",\"access_token\":\"test-access\"}").getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type","application/json");
            exchange.sendResponseHeaders(200,body.length); exchange.getResponseBody().write(body); exchange.close();
        });
        server.createContext("/auth/revoke",exchange -> {
            revoke.set(new String(exchange.getRequestBody().readAllBytes(),StandardCharsets.UTF_8));
            exchange.sendResponseHeaders(200,-1); exchange.close();
        });
        server.start();
        try {
            var service=new AppleTokenRevocation(WebClient.builder(),"app.truearena.truearena","TEAM123","KEY123",encoded,
                    "http://127.0.0.1:"+server.getAddress().getPort());
            var token=Jwts.parser().verifyWith((ECPublicKey)pair.getPublic()).build()
                    .parseSignedClaims(service.clientSecret());
            assertThat(token.getHeader().getKeyId()).isEqualTo("KEY123");
            assertThat(token.getPayload().getIssuer()).isEqualTo("TEAM123");
            assertThat(token.getPayload().getSubject()).isEqualTo("app.truearena.truearena");
            assertThat(token.getPayload().getAudience()).containsExactly("https://appleid.apple.com");
            assertThat(token.getPayload().getExpiration().toInstant().minusSeconds(300))
                    .isEqualTo(token.getPayload().getIssuedAt().toInstant());
            service.revoke("fresh grant","apple-player").block(Duration.ofSeconds(5));
            assertThat(grant.get()).contains("code=fresh+grant","grant_type=authorization_code","client_id=app.truearena.truearena");
            assertThat(revoke.get()).contains("token=test-refresh","token_type_hint=refresh_token");
            revoke.set(null);
            assertThatThrownBy(()->service.revoke("another grant","different-player").block(Duration.ofSeconds(5)))
                    .isInstanceOf(ResponseStatusException.class);
            assertThat(revoke.get()).isNull();
        } finally { server.stop(0); }
    }

    @Test void failsClosedWithoutPrivateSigningConfiguration() {
        var service=new AppleTokenRevocation(WebClient.builder(),"app.truearena.truearena","","","","http://127.0.0.1:1");
        assertThat(service.configured()).isFalse();
        assertThatThrownBy(()->service.revoke("code","apple-player").block()).isInstanceOfSatisfying(ResponseStatusException.class,
                error -> assertThat(error.getStatusCode().value()).isEqualTo(503));
    }
}
