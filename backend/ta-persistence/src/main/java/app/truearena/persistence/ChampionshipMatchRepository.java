package app.truearena.persistence;

import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

public interface ChampionshipMatchRepository extends ReactiveCrudRepository<ChampionshipMatchRow, UUID> {
    Flux<ChampionshipMatchRow> findByChampionshipIdOrderByRoundAscPositionAsc(UUID championshipId);
    Flux<ChampionshipMatchRow> findByChampionshipIdAndRoundOrderByPositionAsc(UUID championshipId, int round);
    Mono<ChampionshipMatchRow> findByRoomId(UUID roomId);
}
