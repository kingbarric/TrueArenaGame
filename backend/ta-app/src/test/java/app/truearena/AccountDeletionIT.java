package app.truearena;
import app.truearena.api.calls.VoiceSessionService;
import app.truearena.api.auth.*;
import app.truearena.api.storage.*;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.test.context.ActiveProfiles;
import java.time.Duration;
import java.util.Map;
import app.truearena.api.calls.CallRingService;
import app.truearena.api.room.RoomService;
import app.truearena.api.ws.GameOrchestrator;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.persistence.*;
import app.truearena.voice.LiveKitRoomAdmin;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.web.server.ResponseStatusException;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import reactor.core.publisher.Mono;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
@Tag("integration")
@ActiveProfiles("test")
class AccountDeletionIT {
    private static final boolean EXTERNAL = System.getProperty("it.r2dbc.url") != null;
    private static final PostgreSQLContainer<?> POSTGRES = EXTERNAL ? null : new PostgreSQLContainer<>("postgres:16");
    private static final GenericContainer<?> REDIS = EXTERNAL ? null
            : new GenericContainer<>("redis:7").withExposedPorts(6379);

    static {
        if (!EXTERNAL) {
            POSTGRES.start();
            REDIS.start();
        }
    }

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        if (EXTERNAL) {
            r.add("spring.r2dbc.url", () -> System.getProperty("it.r2dbc.url"));
            r.add("spring.r2dbc.username", () -> System.getProperty("it.db.user"));
            r.add("spring.r2dbc.password", () -> System.getProperty("it.db.password"));
            r.add("spring.flyway.url", () -> System.getProperty("it.jdbc.url"));
            r.add("spring.flyway.user", () -> System.getProperty("it.db.user"));
            r.add("spring.flyway.password", () -> System.getProperty("it.db.password"));
            r.add("spring.data.redis.host", () -> System.getProperty("it.redis.host", "localhost"));
            r.add("spring.data.redis.port", () -> System.getProperty("it.redis.port", "6379"));
            r.add("spring.data.redis.database", () -> System.getProperty("it.redis.database", "0"));
            return;
        }
        r.add("spring.r2dbc.url", () -> "r2dbc:postgresql://" + POSTGRES.getHost() + ":"
                + POSTGRES.getFirstMappedPort() + "/" + POSTGRES.getDatabaseName());
        r.add("spring.r2dbc.username", POSTGRES::getUsername);
        r.add("spring.r2dbc.password", POSTGRES::getPassword);
        r.add("spring.flyway.url", POSTGRES::getJdbcUrl);
        r.add("spring.flyway.user", POSTGRES::getUsername);
        r.add("spring.flyway.password", POSTGRES::getPassword);
        r.add("spring.data.redis.host", REDIS::getHost);
        r.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
    }


    @Autowired UserRepository users;
    @Autowired DatabaseClient db;
    @Autowired JwtService jwt;
    @Autowired AccountDeletionService deletion;
    @Autowired AccountSessionGuard guard;
    @Autowired AccountMediaErasure media;
    @MockBean LiveKitRoomAdmin livekit;
    @MockBean AppleAuthService appleAuth;
    @MockBean AppleTokenRevocation appleRevocation;
    @MockBean ObjectStorage storage;
    @LocalServerPort int port;

    @BeforeEach void mocks() {
        when(livekit.remove(anyString(),anyString())).thenReturn(Mono.empty());
        when(storage.enabled()).thenReturn(false);
        when(appleRevocation.configured()).thenReturn(true);
    }
    WebTestClient http() { return WebTestClient.bindToServer().baseUrl("http://localhost:"+port)
            .responseTimeout(Duration.ofSeconds(30)).build(); }
    UUID person() {
        String tag=UUID.randomUUID().toString().replace("-","");
        return users.save(UserRow.newUser(null,tag+"@delete.test","Deletion player","d_"+tag)).block().id();
    }
    void sql(String statement) { db.sql(statement).fetch().rowsUpdated().block(); }
    long count(String statement) { return db.sql(statement).map((r,m)->r.get(0,Long.class)).one().block(); }
    AccountDeletionService.Confirmation confirm() { return new AccountDeletionService.Confirmation(true,null,null,null); }

    @Test void erasesPersonalContentButPreservesOtherPlayersAndTheirResults() {
        UUID u=person(), other=person(), group=UUID.randomUUID(), room=UUID.randomUUID(), game=UUID.randomUUID();
        UUID match=UUID.randomUUID(), huud=UUID.randomUUID(), cup=UUID.randomUUID(), look=UUID.randomUUID();
        sql("INSERT INTO groups(id,name,created_by) VALUES ('"+group+"','Private group','"+u+"')");
        sql("INSERT INTO rooms(id,code,host_id,status) VALUES ('"+room+"','"+room+"','"+u+"','in_game')");
        sql("INSERT INTO room_members(room_id,user_id) VALUES ('"+room+"','"+u+"'),('"+room+"','"+other+"')");
        sql("INSERT INTO game_sessions(id,room_id,config,catalog_version,rng_seed) VALUES ('"+game+"','"+room+"','{}',1,1)");
        sql("INSERT INTO game_events(game_session_id,seq,type,payload,visibility_scope) VALUES ('"+game+"',1,'player','{\"userId\":\""+u+"\"}','public')");
        sql("INSERT INTO roles(game_session_id,user_id,role_type) VALUES ('"+game+"','"+u+"','faithful')");
        sql("INSERT INTO votes(game_session_id,round,voter_id,target_id) VALUES ('"+game+"',1,'"+other+"','"+u+"')");
        sql("INSERT INTO game_results(game_session_id,winning_side,per_player_outcome) VALUES ('"+game+"','faithful','{\""+u+"\":\"won\",\""+other+"\":\"lost\"}')");
        sql("INSERT INTO match_records(id,game_session_id,room_id,game_type,ranked,unranked_reason,player_count) VALUES ('"+match+"','"+game+"','"+room+"','chess',false,'casual',2)");
        sql("INSERT INTO match_participants(match_id,user_id,outcome) VALUES ('"+match+"','"+u+"','won'),('"+match+"','"+other+"','lost')");
        sql("INSERT INTO huud_spaces(id,code,name,owner_id,created_by) VALUES ('"+huud+"','"+huud+"','Personal Huud','"+u+"','"+u+"')");
        sql("INSERT INTO championships(id,code,name,game_type,size,visibility,scheduled_at,creator_id,champion_id) VALUES ('"+cup+"','"+cup+"','Cup','chess',4,'private',now(),'"+u+"','"+u+"')");
        sql("INSERT INTO championship_participants(championship_id,user_id,slot) VALUES ('"+cup+"','"+u+"',0)");
        sql("INSERT INTO championship_matches(championship_id,round,position,player_a,player_b,winner_id,status) VALUES ('"+cup+"',1,0,'"+u+"','"+other+"','"+u+"','completed')");
        sql("INSERT INTO championship_badges(championship_id,user_id) VALUES ('"+cup+"','"+u+"')");
        sql("INSERT INTO slay_looks(id,user_id,look,catalog_version,snapshot_key) VALUES ('"+look+"','"+u+"','{}',1,'slay/snapshots/"+look+".png')");
        sql("INSERT INTO slay_reward_claims(user_id,ref) VALUES ('"+u+"','test')");
        sql("INSERT INTO content_reports(reporter_id,subject_type,subject_id,reason) VALUES ('"+u+"','profile','"+other+"','test')");
        sql("INSERT INTO google_accounts(subject,user_id) VALUES ('"+u+"','"+u+"')");
        sql("INSERT INTO feed_posts(author_id,body) VALUES ('"+u+"','personal content')");
        sql("INSERT INTO user_notifications(user_id,type,title,body,data) VALUES ('"+other+"','test','test','copy','{\"userId\":\""+u+"\"}')");
        String access=jwt.issueAccess(u), refresh=jwt.issueRefresh(u);
        deletion.delete(u,confirm()).block(Duration.ofSeconds(30));
        assertThat(users.findById(u).block()).isNull();
        assertThat(users.findById(other).block()).isNotNull();
        assertThat(count("SELECT count(*) FROM match_participants WHERE user_id='"+other+"'")).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM game_events WHERE game_session_id='"+game+"'")).isZero();
        assertThat(count("SELECT count(*) FROM game_results WHERE per_player_outcome ? '"+u+"'")).isZero();
        assertThat(count("SELECT count(*) FROM groups WHERE id='"+group+"'")).isZero();
        assertThat(count("SELECT count(*) FROM huud_spaces WHERE id='"+huud+"'")).isZero();
        assertThat(count("SELECT count(*) FROM account_media_erasure WHERE object_key='slay/snapshots/"+look+".png'")).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM championships WHERE id='"+cup+"' AND champion_id IS NULL")).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM user_notifications WHERE data::text LIKE '%"+u+"%'")).isZero();
        http().get().uri("/api/v1/me").headers(h->h.setBearerAuth(access)).exchange().expectStatus().isUnauthorized();
        http().post().uri("/api/v1/auth/refresh").bodyValue(Map.of("refreshToken",refresh)).exchange().expectStatus().isUnauthorized();
    }

    @Test void guestIsErasedAndCannotBeRestoredByOldDeviceOrToken() {
        String device=UUID.randomUUID().toString();
        UUID u=users.save(UserRow.newGuest(device,"Guest","g_"+device.replace("-",""))).block().id();
        String token=jwt.issueAccess(u);
        http().method(org.springframework.http.HttpMethod.DELETE).uri("/api/v1/me/account")
                .headers(h->h.setBearerAuth(token)).bodyValue(Map.of("confirmed",true))
                .exchange().expectStatus().isNoContent();
        assertThat(users.findByDeviceId(device).block()).isNull();
        assertThat(guard.exists(u).block()).isFalse();
    }

    @Test void requiresConfirmationAndRejectsUnauthenticatedDeletion() {
        UUID u=person();
        http().method(org.springframework.http.HttpMethod.DELETE).uri("/api/v1/me/account")
                .bodyValue(Map.of("confirmed",true)).exchange().expectStatus().isUnauthorized();
        http().method(org.springframework.http.HttpMethod.DELETE).uri("/api/v1/me/account")
                .headers(h->h.setBearerAuth(jwt.issueAccess(u))).bodyValue(Map.of("confirmed",false))
                .exchange().expectStatus().isBadRequest();
        assertThat(users.findById(u).block()).isNotNull();
    }

    @Test void refusesWrongAppleIdentityBeforeRevocationOrErasure() {
        UUID u=person();
        sql("INSERT INTO apple_accounts(subject,user_id) VALUES ('apple-"+u+"','"+u+"')");
        when(appleAuth.verify("id-token","nonce")).thenReturn(Mono.just(new AppleAuthService.AppleIdentity("someone-else",null)));
        assertThatThrownBy(()->deletion.delete(u,new AccountDeletionService.Confirmation(true,"id-token","nonce","grant")).block())
                .isInstanceOf(ResponseStatusException.class);
        assertThat(users.findById(u).block()).isNotNull();
        verify(appleRevocation,never()).revoke(any(),any());
    }

    @Test void failedAppleRevocationKeepsAccountAndSuccessfulRevocationErasesIt() {
        UUID u=person(); String subject="apple-"+u;
        sql("INSERT INTO apple_accounts(subject,user_id) VALUES ('"+subject+"','"+u+"')");
        when(appleAuth.verify("id-token","nonce")).thenReturn(Mono.just(new AppleAuthService.AppleIdentity(subject,null)));
        when(appleRevocation.revoke("grant",subject)).thenReturn(Mono.error(new IllegalStateException("unavailable")));
        var confirmation=new AccountDeletionService.Confirmation(true,"id-token","nonce","grant");
        assertThatThrownBy(()->deletion.delete(u,confirmation).block()).isInstanceOf(IllegalStateException.class);
        assertThat(users.findById(u).block()).isNotNull();
        when(appleRevocation.revoke("grant",subject)).thenReturn(Mono.empty());
        deletion.delete(u,confirmation).block();
        assertThat(users.findById(u).block()).isNull();
        assertThat(count("SELECT count(*) FROM apple_accounts WHERE user_id='"+u+"'")).isZero();
    }

    @Test void storageFailureRetainsDurableErasureWorkForRetry() {
        String key="slay/snapshots/"+UUID.randomUUID()+".png";
        sql("INSERT INTO account_media_erasure(object_key) VALUES ('"+key+"')");
        when(storage.delete(anyString())).thenReturn(Mono.error(new IllegalStateException("offline")));
        assertThatThrownBy(()->media.drain().block()).isInstanceOf(IllegalStateException.class);
        assertThat(count("SELECT count(*) FROM account_media_erasure WHERE object_key='"+key+"'")).isEqualTo(1);
        when(storage.delete(anyString())).thenReturn(Mono.empty());
        media.drain().block();
        assertThat(count("SELECT count(*) FROM account_media_erasure WHERE object_key='"+key+"'")).isZero();
    }
    @Test void deletionCannotBeRedirectedToAnotherUserInTheRequestBody() {
        UUID u=person(), other=person();
        http().method(org.springframework.http.HttpMethod.DELETE).uri("/api/v1/me/account")
                .headers(h->h.setBearerAuth(jwt.issueAccess(u)))
                .bodyValue(Map.of("confirmed",true,"userId",other.toString()))
                .exchange().expectStatus().isNoContent();
        assertThat(users.findById(u).block()).isNull();
        assertThat(users.findById(other).block()).isNotNull();
    }

    @Test void deletionFailureRollsBackContentAndMediaQueueChanges() {
        UUID u=person(), look=UUID.randomUUID();
        sql("INSERT INTO feed_posts(author_id,body) VALUES ('"+u+"','must survive rollback')");
        sql("INSERT INTO slay_looks(id,user_id,look,catalog_version,snapshot_key) VALUES ('"+look+"','"+u+"','{}',1,'rollback/"+look+".png')");
        sql("CREATE TABLE deletion_failure_probe(user_id UUID REFERENCES users(id))");
        try {
            sql("INSERT INTO deletion_failure_probe VALUES ('"+u+"')");
            assertThatThrownBy(()->deletion.delete(u,confirm()).block()).isInstanceOf(Exception.class);
            assertThat(users.findById(u).block()).isNotNull();
            assertThat(count("SELECT count(*) FROM feed_posts WHERE author_id='"+u+"'")).isEqualTo(1);
            assertThat(count("SELECT count(*) FROM slay_looks WHERE user_id='"+u+"'")).isEqualTo(1);
            assertThat(count("SELECT count(*) FROM account_media_erasure WHERE object_key='rollback/"+look+".png'")).isZero();
        } finally { sql("DROP TABLE deletion_failure_probe"); }
    }

    @Test void savedBotsAreErasedAndOpponentAdvancesWhenPlayerDeletesDuringTournament() {
        UUID u=person(), other=person(), cup=UUID.randomUUID(), voice=UUID.randomUUID();
        UUID bot=users.save(UserRow.newBot("Personal agent","agent_"+UUID.randomUUID().toString().replace("-",""),u,"chess","easy")).block().id();
        sql("INSERT INTO championships(id,code,name,game_type,size,visibility,scheduled_at,creator_id,status,current_round) VALUES ('"+cup+"','"+cup+"','Cup','chess',4,'private',now()+interval '1 day','"+other+"','running',1)");
        sql("INSERT INTO championship_matches(championship_id,round,position,player_a,player_b,status) VALUES ('"+cup+"',1,0,'"+u+"','"+other+"','active')");
        sql("INSERT INTO voice_sessions(id,room_name,type,owner_id,created_by) VALUES ('"+voice+"','test-"+voice+"','direct','"+u+"','"+u+"')");
        sql("INSERT INTO voice_session_participants(voice_session_id,user_id) VALUES ('"+voice+"','"+u+"'),('"+voice+"','"+other+"')");
        deletion.delete(u,confirm()).block();
        assertThat(users.findById(bot).block()).isNull();
        assertThat(users.findById(other).block()).isNotNull();
        assertThat(count("SELECT count(*) FROM championship_matches WHERE championship_id='"+cup+"' AND player_a IS NULL AND winner_id='"+other+"' AND status='completed'")).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM voice_sessions WHERE id='"+voice+"' AND status='ended'")).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM voice_session_participants WHERE voice_session_id='"+voice+"' AND left_at IS NULL")).isZero();
        verify(livekit).remove("test-"+voice,u.toString());
    }

}
