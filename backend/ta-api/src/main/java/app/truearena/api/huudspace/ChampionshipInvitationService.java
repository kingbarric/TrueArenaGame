package app.truearena.api.huudspace;

import app.truearena.api.championship.ChampionshipService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.ChampionshipRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.reactive.TransactionalOperator;
import reactor.core.publisher.Mono;
import java.util.UUID;

@Service
public class ChampionshipInvitationService {
    private final ChampionshipRepository rows;
    private final ChampionshipService championships;
    private final HuudSpaceService huuds;
    private final TransactionalOperator tx;
    public ChampionshipInvitationService(ChampionshipRepository rows, ChampionshipService championships,
                                         HuudSpaceService huuds, TransactionalOperator tx) {
        this.rows = rows; this.championships = championships; this.huuds = huuds; this.tx = tx;
    }
    public record Accepted(UUID championshipId, UUID huudSpaceId) {}

    public Mono<Accepted> accept(String code, UUID user) {
        if (code == null || !code.matches("(?i)[A-HJ-NP-Z2-9]{8}"))
            return Mono.error(ApiExceptions.notFound("Invitation not found"));
        return rows.findByCode(code.toUpperCase())
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("Invitation not found")))
                .flatMap(c -> {
                    if (!"lobby".equals(c.status()))
                        return Mono.error(ApiExceptions.conflict("Registration is closed"));
                    if (c.huudSpaceId() == null)
                        return championships.register(c, user).thenReturn(new Accepted(c.id(), null));
                    // Registration capacity/bot checks and admission commit together.
                    return tx.transactional(huuds.admitChampionshipInvite(c.huudSpaceId(), c.id(), user)
                                    .then(championships.register(c, user))
                                    .then(huuds.enterLive(c.huudSpaceId(), user, true)))
                            .thenReturn(new Accepted(c.id(), c.huudSpaceId()));
                });
    }
}
