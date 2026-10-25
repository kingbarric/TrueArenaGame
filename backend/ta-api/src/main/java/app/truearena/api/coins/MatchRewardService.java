package app.truearena.api.coins;

import app.truearena.persistence.GameResultRepository;
import app.truearena.api.support.ApiExceptions;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import java.util.UUID;

/** Settles earned coins atomically from stored results; reconnects are safe to retry. */
@Service
public class MatchRewardService {
    private final DatabaseClient db;
    private final GameResultRepository results;
    private final ObjectMapper mapper;
    public record Reward(UUID userId, long amount, long baseAmount, long timeBonus,
                         long elapsedSeconds, boolean vsAgent, UUID gameSessionId) {}
    public MatchRewardService(DatabaseClient db, GameResultRepository results, ObjectMapper mapper) {
        this.db=db; this.results=results; this.mapper=mapper;
    }
    public Flux<Reward> award(UUID sessionId) {
        return results.findByGameSessionId(sessionId).flatMapMany(result -> {
            try {
                var outcomes=mapper.readTree(result.perPlayerOutcome().asString());
                var ids=new java.util.ArrayList<UUID>();
                outcomes.fieldNames().forEachRemaining(raw -> ids.add(UUID.fromString(raw)));
                return Flux.fromIterable(ids).concatMap(id -> awardOne(sessionId,id));
            } catch (Exception e) { return Flux.error(e); }
        });
    }
    private Mono<Reward> awardOne(UUID sessionId, UUID userId) {
        return db.sql("SELECT * FROM award_match_coins(:session,:user)")
            .bind("session",sessionId).bind("user",userId)
            .map((row,meta) -> new Reward(userId,row.get("amount",Long.class),
                row.get("base_amount",Long.class),row.get("time_bonus",Long.class),
                row.get("elapsed_seconds",Long.class),row.get("vs_agent",Boolean.class),sessionId)).one();
    }
    public Mono<Reward> forRoom(UUID roomId, UUID userId) {
        return db.sql("SELECT id FROM game_sessions WHERE room_id=:room ORDER BY started_at DESC NULLS LAST,id DESC LIMIT 1")
            .bind("room",roomId).map((row,meta)->row.get("id",UUID.class)).one()
            .flatMap(session -> awardOne(session,userId))
            .switchIfEmpty(Mono.error(ApiExceptions.notFound("No completed match reward yet")));
    }
}
