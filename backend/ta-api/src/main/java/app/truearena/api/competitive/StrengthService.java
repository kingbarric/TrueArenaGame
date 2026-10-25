package app.truearena.api.competitive;

import app.truearena.api.competitive.CompetitiveDtos.RankView;
import app.truearena.api.competitive.CompetitiveDtos.RanksView;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** One server calculation for cards and strength boards. Never accepts a client score.
 * Glicko-2 remains the competitive rating; /100 is PlayHuud's confidence-adjusted
 * presentation, not an official Glicko scale. Games without a rating use a
 * conservative result estimate. Bots, guests and repeated-opponent farming cannot
 * build this estimate. Geography describes a rank; it never awards skill points.
 */
@Service
public class StrengthService {
    private final DatabaseClient db;
    public StrengthService(DatabaseClient db) { this.db = db; }

    public record StrengthView(int score, String basis, long games, RanksView ranks) {}
    public record Entry(String gameType, UUID userId, String username, String displayName, String avatarUrl,
                        int score, String basis, long games, long wins, long draws, long losses,
                        String countryCode, String regionKey, Integer global, Integer country, Integer region) {
        StrengthView view() {
            String status = games < 10 ? RankView.PROVISIONAL : RankView.RANKED;
            return new StrengthView(score, basis, games, new RanksView(
                    new RankView(global, status),
                    new RankView(country, countryCode == null ? RankView.LOCATION_REQUIRED : status),
                    new RankView(region, regionKey == null ? RankView.LOCATION_REQUIRED : status)));
        }
    }

    // Result estimates use the Wilson 95% lower bound; Glicko uses r - 2*RD
    // (the conservative end of its interval), plus a 15-game confidence ramp.
    // Rank on the unrounded value, then display the bounded integer /100.
    private static final String METRICS = """
        WITH human_matches AS (
          SELECT p.user_id, m.game_type, p.outcome,
            row_number() OVER (PARTITION BY p.user_id, m.game_type,
              date_trunc('day', m.completed_at AT TIME ZONE 'UTC'),
              (SELECT string_agg(o.user_id::text, ',' ORDER BY o.user_id)
                 FROM match_participants o WHERE o.match_id=m.id AND o.user_id<>p.user_id)
              ORDER BY m.completed_at, m.id) AS pair_day
          FROM match_records m JOIN match_participants p ON p.match_id=m.id
          JOIN users u ON u.id=p.user_id
          WHERE NOT u.is_bot AND NOT u.is_guest
            AND EXISTS (SELECT 1 FROM match_participants o WHERE o.match_id=m.id AND o.user_id<>p.user_id)
            AND NOT EXISTS (SELECT 1 FROM match_participants o JOIN users ou ON ou.id=o.user_id
              WHERE o.match_id=m.id AND (ou.is_bot OR ou.is_guest))
        ), human_stats AS (
          SELECT user_id, game_type, count(*)::double precision AS n,
            count(*) FILTER (WHERE outcome IN ('won','rank:1')) AS wins,
            count(*) FILTER (WHERE outcome='tied') AS draws,
            count(*) FILTER (WHERE outcome NOT IN ('won','rank:1','tied')) AS losses
          FROM human_matches WHERE pair_day<=5 GROUP BY user_id,game_type
        ), known AS (
          SELECT user_id,game_type FROM player_game_stats UNION SELECT user_id,game_type FROM player_game_ratings
        ), inputs AS (
          SELECT k.user_id,k.game_type,coalesce(h.n,0) AS n,
            coalesce(h.wins,0) AS wins,coalesce(h.draws,0) AS draws,coalesce(h.losses,0) AS losses,
            coalesce(r.rated_games_played,0) AS rated_games, r.rating,r.rating_deviation,
            CASE WHEN h.n>0 THEN (h.wins+0.5*h.draws)/h.n ELSE 0 END AS p
          FROM known k JOIN users u ON u.id=k.user_id
          LEFT JOIN human_stats h ON h.user_id=k.user_id AND h.game_type=k.game_type
          LEFT JOIN player_game_ratings r ON r.user_id=k.user_id AND r.game_type=k.game_type
          WHERE NOT u.is_bot AND NOT u.is_guest
        ), game_scores AS (
          SELECT *, CASE WHEN rated_games>0 THEN
              100.0/(1+exp(greatest(-50,least(50,(1500-rating+2*rating_deviation)/400.0))))*(1-exp(-rated_games/15.0))
            WHEN n>0 THEN 100.0*(p+3.8416/(2*n)-1.96*sqrt(p*(1-p)/n+3.8416/(4*n*n)))/(1+3.8416/n)
            ELSE 0 END AS raw_score,
            CASE WHEN rated_games>0 THEN 'glicko2' ELSE 'estimate' END AS basis,
            (CASE WHEN rated_games>0 THEN rated_games ELSE n END)::bigint AS samples
          FROM inputs
        ), metrics AS (
          SELECT user_id,game_type,raw_score,basis,samples,wins,draws,losses FROM game_scores
          UNION ALL
          SELECT user_id,'overall',coalesce(sum(raw_score*least(samples,30))/nullif(sum(least(samples,30)),0),0),
            CASE WHEN min(basis)=max(basis) THEN min(basis) ELSE 'mixed' END,
            sum(samples)::bigint,sum(wins),sum(draws),sum(losses)
          FROM game_scores GROUP BY user_id
        ), located AS (
          SELECT m.*,u.username,u.display_name,u.avatar_url,cp.country_code,
            coalesce(cp.region_code,CASE WHEN cp.city_public THEN lower(cp.city) END) AS region_key
          FROM metrics m JOIN users u ON u.id=m.user_id LEFT JOIN competitive_profiles cp ON cp.user_id=m.user_id
        ), eligible AS (
          SELECT user_id,game_type,
            rank() OVER(PARTITION BY game_type ORDER BY raw_score DESC,samples DESC) AS global_place,
            rank() OVER(PARTITION BY game_type,country_code ORDER BY raw_score DESC,samples DESC) AS country_place,
            rank() OVER(PARTITION BY game_type,country_code,region_key ORDER BY raw_score DESC,samples DESC) AS region_place
          FROM located WHERE samples>=10
        )
        SELECT l.*,e.global_place,
          CASE WHEN l.country_code IS NOT NULL THEN e.country_place END AS country_place,
          CASE WHEN l.country_code IS NOT NULL AND l.region_key IS NOT NULL THEN e.region_place END AS region_place,
          greatest(0,least(100,round(l.raw_score)::int)) AS score
        FROM located l LEFT JOIN eligible e ON e.user_id=l.user_id AND e.game_type=l.game_type
        """;

    public Mono<Map<String, StrengthView>> forUser(UUID user) {
        return db.sql(METRICS + " WHERE l.user_id=:uid").bind("uid",user)
                .map((r,m)->entry(r)).all().collectMap(Entry::gameType,Entry::view);
    }

    public Mono<List<Entry>> top(String gameType) {
        return db.sql(METRICS + " WHERE l.game_type=:game AND e.global_place IS NOT NULL ORDER BY e.global_place,l.user_id LIMIT 20")
                .bind("game",gameType==null?"overall":gameType).map((r,m)->entry(r)).all().collectList();
    }

    public Mono<Entry> own(String gameType,UUID user) {
        return db.sql(METRICS+" WHERE l.game_type=:game AND l.user_id=:uid")
                .bind("game",gameType==null?"overall":gameType).bind("uid",user).map((r,m)->entry(r)).one();
    }

    private static Entry entry(io.r2dbc.spi.Row r) {
        return new Entry(r.get("game_type",String.class),r.get("user_id",UUID.class),r.get("username",String.class),
                r.get("display_name",String.class),r.get("avatar_url",String.class),num(r.get("score")).intValue(),
                r.get("basis",String.class),num(r.get("samples")).longValue(),num(r.get("wins")).longValue(),
                num(r.get("draws")).longValue(),num(r.get("losses")).longValue(),r.get("country_code",String.class),r.get("region_key",String.class),rank(r,"global_place"),rank(r,"country_place"),rank(r,"region_place"));
    }
    private static Integer rank(io.r2dbc.spi.Row r,String key) { return r.get(key)==null?null:num(r.get(key)).intValue(); }
    private static Number num(Object value) { return value instanceof Number n?n:0; }
}
