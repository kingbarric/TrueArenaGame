package app.truearena;
import app.truearena.api.auth.*;
import app.truearena.api.safety.AgeSafetyService;
import app.truearena.persistence.*;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.junit.jupiter.api.*;
import java.util.UUID;
import java.util.Map;
import java.time.Duration;
import static org.assertj.core.api.Assertions.*;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
@Tag("integration") @ActiveProfiles("test")
class MatchRewardsIT {
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
        r.add("truearena.safety.age-enforcement-enabled", () -> "false");
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
    @Autowired app.truearena.api.coins.MatchRewardService rewards;
    @Autowired app.truearena.api.coins.GiftController gifts;
    private UserRow player() {
        String id=UUID.randomUUID().toString();
        return users.save(UserRow.newGuest("reward-it-"+id,"Reward test","rw_"+id.replace("-",""))).block();
    }
    private long balance(UUID user) {
        return db.sql("SELECT coins FROM users WHERE id=:u").bind("u",user)
            .map((row,m)->row.get("coins",Long.class)).one().block();
    }
    private UUID finished(UserRow winner, UserRow loser, long seconds, String reason) {
        UUID room=UUID.randomUUID(), session=UUID.randomUUID();
        db.sql("INSERT INTO rooms(id,code,host_id,status,game_type) VALUES(:r,:c,:u,'ended','chess')")
            .bind("r",room).bind("c",room.toString()).bind("u",winner.id()).fetch().rowsUpdated().block();
        db.sql("INSERT INTO game_sessions(id,room_id,game_type,config,catalog_version,rng_seed,started_at,ended_at) "
            +"VALUES(:s,:r,'chess','{}',1,1,now()-make_interval(secs => :seconds),now())")
            .bind("s",session).bind("r",room).bind("seconds",seconds).fetch().rowsUpdated().block();
        String result="{\""+winner.id()+"\":\"won\",\""+loser.id()+"\":\"lost\"}";
        db.sql("INSERT INTO game_results(game_session_id,winning_side,per_player_outcome) VALUES(:s,'faithful',CAST(:result AS jsonb))")
            .bind("s",session).bind("result",result).fetch().rowsUpdated().block();
        db.sql("INSERT INTO game_events(game_session_id,seq,type,payload,visibility_scope) VALUES(:s,1,'GAME_OVER',CAST(:p AS jsonb),'public')")
            .bind("s",session).bind("p","{\"reason\":\""+reason+"\"}").fetch().rowsUpdated().block();
        return session;
    }
    @Test void rewardsVaryWithServerTimeAndNeverDeductFromLoser() {
        for(long seconds:new long[]{120,300,600,900,15}) {
            var winner=player(); var loser=player();
            UUID session=finished(winner,loser,seconds,"checkmate");
            var receipts=rewards.award(session).collectList().block();
            long expected=seconds==120?80:seconds==300?70:seconds==600?60:50;
            assertThat(receipts).hasSize(2);
            assertThat(balance(winner.id())).isEqualTo(expected);
            assertThat(balance(loser.id())).isEqualTo(10);
        }
    }
    @Test void concurrentRetriesCreditOnlyOnceAndSpectatorsCannotClaim() {
        var winner=player();var loser=player();var spectator=player();
        UUID session=finished(winner,loser,120,"checkmate");
        reactor.core.publisher.Flux.range(0,12).flatMap(i->rewards.award(session),12).then().block();
        assertThat(balance(winner.id())).isEqualTo(80);
        assertThat(balance(loser.id())).isEqualTo(10);
        assertThat(db.sql("SELECT count(*) n FROM coin_transactions WHERE ref_id=:s")
            .bind("s",session).map((row,m)->row.get("n",Long.class)).one().block()).isEqualTo(2);
        UUID room=db.sql("SELECT room_id FROM game_sessions WHERE id=:s").bind("s",session)
            .map((row,m)->row.get("room_id",UUID.class)).one().block();
        assertThatThrownBy(()->rewards.forRoom(room,spectator.id()).block()).hasMessageContaining("404");
        assertThat(balance(spectator.id())).isZero();
    }
    @Test void resignationHasNoSpeedBonusAndAgentsCannotGenerateCoins() {
        var winner=player();var loser=player();
        rewards.award(finished(winner,loser,120,"resigned")).then().block();
        assertThat(balance(winner.id())).isEqualTo(50);
        var agent=player();var human=player();
        db.sql("UPDATE users SET is_bot=true WHERE id=:u").bind("u",agent.id()).fetch().rowsUpdated().block();
        var receipts=rewards.award(finished(human,agent,120,"checkmate")).collectList().block();
        assertThat(receipts).hasSize(1);assertThat(receipts.getFirst().amount()).isZero();
        assertThat(balance(human.id())).isZero();assertThat(balance(agent.id())).isZero();
    }
    @Test void giftsTransferExistingCoinsWithoutIncreasingTotalOrLifetime() {
        assertThat(app.truearena.api.coins.CoinService.WELCOME_GRANT).isEqualTo(100);
        var from=player();var to=player();
        db.sql("UPDATE users SET is_guest=false,email=id::text||'@example.invalid' WHERE id IN (:from,:to)").bind("from",from.id()).bind("to",to.id()).fetch().rowsUpdated().block();
        db.sql("UPDATE users SET coins=100 WHERE id=:u").bind("u",from.id()).fetch().rowsUpdated().block();
        gifts.give(from.id(),to.id()).block();
        assertThat(balance(from.id())).isEqualTo(97);assertThat(balance(to.id())).isEqualTo(3);
        assertThat(users.lifetimeCoinsOf(to.id()).block()).isZero();
    }
    @Test void failedLedgerWriteRollsBackReceiptAndBalanceTogether() {
        var winner=player();var loser=player();UUID session=finished(winner,loser,120,"checkmate");
        String constraint="reward_it_"+UUID.randomUUID().toString().replace("-","");
        db.sql("ALTER TABLE coin_transactions ADD CONSTRAINT "+constraint+" CHECK(ref_id <> '"+session+"'::uuid)")
            .fetch().rowsUpdated().block();
        try {
            assertThatThrownBy(()->rewards.award(session).then().block()).isNotNull();
            assertThat(balance(winner.id())).isZero();
            assertThat(db.sql("SELECT count(*) n FROM match_coin_rewards WHERE game_session_id=:s")
                .bind("s",session).map((row,m)->row.get("n",Long.class)).one().block()).isZero();
        } finally { db.sql("ALTER TABLE coin_transactions DROP CONSTRAINT "+constraint).fetch().rowsUpdated().block(); }
        rewards.award(session).then().block();assertThat(balance(winner.id())).isEqualTo(80);
    }

}
