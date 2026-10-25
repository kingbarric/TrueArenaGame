package app.truearena.api.huudspace;

import app.truearena.api.championship.ChampionshipService;
import app.truearena.persistence.ChampionshipRepository;
import app.truearena.persistence.ChampionshipRow;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.reactive.TransactionalOperator;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.assertj.core.api.Assertions.assertThat;

class ChampionshipInvitationServiceTest {
    final ChampionshipRepository rows = mock(ChampionshipRepository.class);
    final ChampionshipService cups = mock(ChampionshipService.class);
    final HuudSpaceService huuds = mock(HuudSpaceService.class);
    final TransactionalOperator tx = mock(TransactionalOperator.class);
    final ChampionshipInvitationService service = new ChampionshipInvitationService(rows, cups, huuds, tx);
    final UUID id = UUID.randomUUID(), huud = UUID.randomUUID(), guest = UUID.randomUUID();
    ChampionshipRow row(String status, UUID space) {
        return new ChampionshipRow(id, "ABCD2345", "Friday crown", "chess", 8, "private", Instant.now().plusSeconds(600),
                UUID.randomUUID(), status, 0, null, Instant.now(), null, space, "simultaneous", true, 180);
    }
    @SuppressWarnings("unchecked") @BeforeEach void transactions() {
        when(tx.transactional(any(Mono.class))).thenAnswer(call -> call.getArgument(0));
    }
    @Test void acceptingAHuudCupRegistersTheSameHumanGuestAndOpensItsHuud() {
        var c = row("lobby", huud);
        when(rows.findByCode("ABCD2345")).thenReturn(Mono.just(c));
        when(huuds.admitChampionshipInvite(huud, id, guest)).thenReturn(Mono.empty());
        when(cups.register(c, guest)).thenReturn(Mono.empty());
        when(huuds.enterLive(huud, guest, true)).thenReturn(Mono.just(true));
        StepVerifier.create(service.accept("abcd2345", guest)).assertNext(result -> {
            assertThat(result.championshipId()).isEqualTo(id);
            assertThat(result.huudSpaceId()).isEqualTo(huud);
        }).verifyComplete();
    }
    @Test void fullOrBotRefusalDoesNotEnterTheLiveHuud() {
        var c = row("lobby", huud);
        when(rows.findByCode("ABCD2345")).thenReturn(Mono.just(c));
        when(huuds.admitChampionshipInvite(huud, id, guest)).thenReturn(Mono.empty());
        when(cups.register(c, guest)).thenReturn(Mono.error(new ResponseStatusException(org.springframework.http.HttpStatus.CONFLICT)));
        var entered = reactor.test.publisher.PublisherProbe.of(Mono.just(true));
        when(huuds.enterLive(huud, guest, true)).thenReturn(entered.mono());
        StepVerifier.create(service.accept(c.code(), guest)).expectError(ResponseStatusException.class).verify();
        entered.assertWasNotSubscribed();
        verify(tx).transactional(any(Mono.class));
    }
    @Test void expiredOrMalformedInvitationsCannotGrantHuudMembership() {
        when(rows.findByCode("ABCD2345")).thenReturn(Mono.just(row("cancelled", huud)));
        StepVerifier.create(service.accept("ABCD2345", guest)).expectError(ResponseStatusException.class).verify();
        StepVerifier.create(service.accept("../../private", guest)).expectError(ResponseStatusException.class).verify();
        verifyNoInteractions(huuds, cups);
    }
    @Test void removedOrBlockedPeopleCannotRegisterThroughTheLink() {
        var c = row("lobby", huud);
        when(rows.findByCode(c.code())).thenReturn(Mono.just(c));
        when(huuds.admitChampionshipInvite(huud, id, guest)).thenReturn(Mono.error(new ResponseStatusException(org.springframework.http.HttpStatus.FORBIDDEN)));
        var registered = reactor.test.publisher.PublisherProbe.<Void>empty();
        when(cups.register(c, guest)).thenReturn(registered.mono());
        when(huuds.enterLive(huud, guest, true)).thenReturn(Mono.just(true));
        StepVerifier.create(service.accept(c.code(), guest)).expectError(ResponseStatusException.class).verify();
        registered.assertWasNotSubscribed();
    }
    @Test void aStandaloneInvitationUsesTheSameRegistrationPolicy() {
        var c = row("lobby", null);
        when(rows.findByCode(c.code())).thenReturn(Mono.just(c));
        when(cups.register(c, guest)).thenReturn(Mono.empty());
        StepVerifier.create(service.accept(c.code(), guest)).assertNext(r -> assertThat(r.huudSpaceId()).isNull()).verifyComplete();
        verifyNoInteractions(huuds);
    }
}
