package app.truearena.api.room;

import app.truearena.api.auth.JwtService;
import app.truearena.api.bot.BotRuntimeRegistry;
import app.truearena.api.coins.CoinService;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.ws.GameOrchestrator;
import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.RoomMemberRepository;
import app.truearena.persistence.RoomMemberRow;
import app.truearena.persistence.RoomRepository;
import app.truearena.persistence.RoomRow;
import app.truearena.persistence.UserRepository;
import app.truearena.persistence.UserRow;
import app.truearena.room.RoomRuntime;
import app.truearena.room.RoomRuntimeRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Room lifecycle coverage (create/join/abandon/discoverable) — previously untested.
 * Mockito-mocked repositories + {@link StepVerifier}, the same pattern established by
 * {@code WhotCallServiceTest} for a service with this repository-dependency shape.
 */
class RoomServiceTest {

    private final RoomRepository rooms = mock(RoomRepository.class);
    private final RoomMemberRepository members = mock(RoomMemberRepository.class);
    private final UserRepository users = mock(UserRepository.class);
    private final JwtService jwt = mock(JwtService.class);
    private final InboxRegistry inbox = mock(InboxRegistry.class);
    private final FriendRepository friends = mock(FriendRepository.class);
    private final RoomRuntimeRegistry runtimes = mock(RoomRuntimeRegistry.class);
    private final CoinService coins = mock(CoinService.class);
    private final BotRuntimeRegistry botRuntimes = mock(BotRuntimeRegistry.class);
    private final GameOrchestrator games = mock(GameOrchestrator.class);
    private final RoomService service = new RoomService(rooms, members, users, jwt, inbox, friends, runtimes, coins,
            botRuntimes, games);

    private UserRow realUser(UUID id) {
        return new UserRow(id, "Player", null, null, null, "player", false, null, false, null, null, null, null, null);
    }

    private UserRow guest(UUID id) {
        return new UserRow(id, "Guest", null, null, null, "guest", true, "device-1", false, null, null, null, null, null);
    }

    private RoomRow room(UUID id, UUID hostId, long stake) {
        return new RoomRow(id, "ABCDEF", null, hostId, "lobby", "truearena", stake, null, Instant.now());
    }

    /** Every `rooms.save(...)` in the flows under test gets the same stable id back. */
    private void stubRoomSave(UUID roomId) {
        when(rooms.save(any(RoomRow.class))).thenAnswer(inv -> {
            RoomRow arg = inv.getArgument(0);
            return Mono.just(new RoomRow(roomId, arg.code(), arg.groupId(), arg.hostId(), arg.status(),
                    arg.gameType(), arg.stakeCoins(), arg.gameConfig(), arg.createdAt()));
        });
    }

    // ---------------------------------------------------------------- create

    @Test
    void create_rejectsAGuestHost() {
        UUID hostId = UUID.randomUUID();
        when(users.findById(hostId)).thenReturn(Mono.just(guest(hostId)));

        StepVerifier.create(service.create(hostId, null, "truearena", null, null))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 403)
                .verify();
    }

    @Test
    void create_rejectsAnUnknownGameType() {
        UUID hostId = UUID.randomUUID();

        StepVerifier.create(service.create(hostId, null, "not-a-real-game", null, null))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 400)
                .verify();

        verifyNoInteractions(users); // rejected before even looking the host up
    }

    @Test
    void create_rejectsANegativeStake() {
        UUID hostId = UUID.randomUUID();

        StepVerifier.create(service.create(hostId, null, "truearena", -5L, null))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 400)
                .verify();
    }

    @Test
    void create_retriesOnRoomCodeCollisionThenSucceeds() {
        UUID hostId = UUID.randomUUID();
        UUID roomId = UUID.randomUUID();
        when(users.findById(hostId)).thenReturn(Mono.just(realUser(hostId)));
        when(rooms.findByCode(anyString()))
                .thenReturn(Mono.just(room(UUID.randomUUID(), UUID.randomUUID(), 0))) // first candidate collides
                .thenReturn(Mono.empty());                                            // retry is free
        stubRoomSave(roomId);
        when(members.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));
        when(members.findByRoomId(roomId)).thenReturn(Flux.empty());
        when(inbox.callCompanionsOf(hostId)).thenReturn(Set.of());
        when(jwt.issueAccess(hostId)).thenReturn("token");

        StepVerifier.create(service.create(hostId, null, "truearena", null, null))
                .expectNextMatches(v -> v.id().equals(roomId))
                .verifyComplete();

        verify(rooms, times(2)).findByCode(anyString());
    }

    @Test
    void create_failsAfterExhaustingRoomCodeRetries() {
        UUID hostId = UUID.randomUUID();
        when(users.findById(hostId)).thenReturn(Mono.just(realUser(hostId)));
        when(rooms.findByCode(anyString())).thenReturn(Mono.just(room(UUID.randomUUID(), UUID.randomUUID(), 0))); // always collides

        StepVerifier.create(service.create(hostId, null, "truearena", null, null))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 409)
                .verify();

        verify(rooms, times(6)).findByCode(anyString()); // allocateCode(5): the initial try + 5 retries
    }

    @Test
    void create_rollsBackMembershipAndRoomWhenTheStakeDebitFails() {
        UUID hostId = UUID.randomUUID();
        UUID roomId = UUID.randomUUID();
        when(users.findById(hostId)).thenReturn(Mono.just(realUser(hostId)));
        when(rooms.findByCode(anyString())).thenReturn(Mono.empty());
        stubRoomSave(roomId);
        when(members.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));
        when(coins.debit(eq(hostId), eq(100L), any(), eq(roomId)))
                .thenReturn(Mono.error(new RuntimeException("insufficient")));
        when(members.deleteByRoomIdAndUserId(roomId, hostId)).thenReturn(Mono.empty());
        when(members.countByRoomId(roomId)).thenReturn(Mono.just(0L));
        when(rooms.deleteById(roomId)).thenReturn(Mono.empty());

        StepVerifier.create(service.create(hostId, null, "truearena", 100L, null))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 409
                        && rse.getReason() != null && rse.getReason().contains("not enough coins"))
                .verify();

        verify(members).deleteByRoomIdAndUserId(roomId, hostId);
        verify(rooms).deleteById(roomId);
    }

    // ---------------------------------------------------------------- join

    @Test
    void join_failsWithNotFoundForAnUnknownCode() {
        when(rooms.findByCode("ZZZZZZ")).thenReturn(Mono.empty());

        StepVerifier.create(service.join("zzzzzz", UUID.randomUUID(), "nick"))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 404)
                .verify();
    }

    @Test
    void join_isIdempotentForAnExistingMember() {
        UUID roomId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        RoomRow r = room(roomId, UUID.randomUUID(), 0);
        when(rooms.findByCode("ABCDEF")).thenReturn(Mono.just(r));
        when(members.findByRoomIdAndUserId(roomId, userId))
                .thenReturn(Mono.just(RoomMemberRow.of(roomId, userId, "nick")));
        // Built eagerly as the switchIfEmpty argument even though the member-found
        // branch never actually subscribes to it — needs a non-null stub regardless.
        when(members.countByRoomId(roomId)).thenReturn(Mono.just(1L));
        when(members.findByRoomId(roomId)).thenReturn(Flux.empty());
        when(jwt.issueAccess(userId)).thenReturn("token");

        StepVerifier.create(service.join("abcdef", userId, "nick"))
                .expectNextMatches(v -> v.id().equals(roomId))
                .verifyComplete();

        verify(members, never()).save(any());
    }

    @Test
    void join_rejectsAFullRoom() {
        UUID roomId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        when(rooms.findByCode("ABCDEF")).thenReturn(Mono.just(room(roomId, UUID.randomUUID(), 0)));
        when(members.findByRoomIdAndUserId(roomId, userId)).thenReturn(Mono.empty());
        when(members.countByRoomId(roomId)).thenReturn(Mono.just(16L));

        StepVerifier.create(service.join("abcdef", userId, "nick"))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 409)
                .verify();
    }

    @Test
    void join_rejectsAFifthLudoSeat() {
        UUID roomId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        RoomRow ludo = new RoomRow(roomId, "ABCDEF", null, UUID.randomUUID(),
                "lobby", "ludo", 0, null, Instant.now());
        when(rooms.findByCode("ABCDEF")).thenReturn(Mono.just(ludo));
        when(members.findByRoomIdAndUserId(roomId, userId)).thenReturn(Mono.empty());
        when(members.countByRoomId(roomId)).thenReturn(Mono.just(4L));

        StepVerifier.create(service.join("abcdef", userId, "nick"))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 409)
                .verify();
    }

    @Test
    void join_addsAMembershipForANewJoiner() {
        UUID roomId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        when(rooms.findByCode("ABCDEF")).thenReturn(Mono.just(room(roomId, UUID.randomUUID(), 0)));
        when(members.findByRoomIdAndUserId(roomId, userId)).thenReturn(Mono.empty());
        when(members.countByRoomId(roomId)).thenReturn(Mono.just(1L));
        when(members.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));
        when(members.findByRoomId(roomId)).thenReturn(Flux.empty());
        when(jwt.issueAccess(userId)).thenReturn("token");

        StepVerifier.create(service.join("abcdef", userId, "nick"))
                .expectNextMatches(v -> v.id().equals(roomId))
                .verifyComplete();

        verify(members).save(any());
    }

    // ---------------------------------------------------------------- abandon

    @Test
    void abandon_onlyTheHostCanAbandon() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        when(rooms.findById(roomId)).thenReturn(Mono.just(room(roomId, hostId, 0)));

        StepVerifier.create(service.abandon(roomId, UUID.randomUUID()))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 403)
                .verify();
    }

    @Test
    void abandon_succeedsWhenNoRuntimeIsRegistered() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        when(rooms.findById(roomId)).thenReturn(Mono.just(room(roomId, hostId, 0)));
        when(runtimes.find(roomId)).thenReturn(Optional.empty());
        when(members.findByRoomId(roomId)).thenReturn(Flux.empty());
        when(members.deleteByRoomId(roomId)).thenReturn(Mono.empty());
        when(rooms.deleteById(roomId)).thenReturn(Mono.empty());

        StepVerifier.create(service.abandon(roomId, hostId)).verifyComplete();

        verify(rooms).deleteById(roomId);
    }

    @Test
    void abandon_succeedsWhenTheRuntimeExistsButHasNotStarted() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        when(rooms.findById(roomId)).thenReturn(Mono.just(room(roomId, hostId, 0)));
        RoomRuntime rt = new RoomRuntime(roomId, hostId.toString()); // never .start()ed -> started() == false
        when(runtimes.find(roomId)).thenReturn(Optional.of(rt));
        when(members.findByRoomId(roomId)).thenReturn(Flux.empty());
        when(members.deleteByRoomId(roomId)).thenReturn(Mono.empty());
        when(rooms.deleteById(roomId)).thenReturn(Mono.empty());

        StepVerifier.create(service.abandon(roomId, hostId)).verifyComplete();

        verify(rooms).deleteById(roomId);
    }

    @Test
    void abandon_releasesAgentsInAnUnstakedLobby() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID agentId = UUID.randomUUID();
        when(rooms.findById(roomId)).thenReturn(Mono.just(room(roomId, hostId, 0)));
        when(runtimes.find(roomId)).thenReturn(Optional.empty());
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, agentId, "Agent")));
        when(members.deleteByRoomId(roomId)).thenReturn(Mono.empty());
        when(rooms.deleteById(roomId)).thenReturn(Mono.empty());

        StepVerifier.create(service.abandon(roomId, hostId)).verifyComplete();

        verify(botRuntimes).stopRoom(roomId);
        verify(runtimes).remove(roomId);
    }

    @Test
    void leaveBotDraughtsRoom_forfeitsAndReleasesOwnedAgent() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID agentId = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "draughts", 0, null, Instant.now());
        UserRow agent = new UserRow(agentId, "Agent", null, null, null, "agent", false, null,
                true, hostId, "all", "easy", null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, agentId, "Agent")));
        when(users.findById(agentId)).thenReturn(Mono.just(agent));
        when(games.forfeitBotDraughtsRoom(roomId, hostId)).thenReturn(Mono.just(true));
        when(runtimes.find(roomId)).thenReturn(Optional.empty());

        StepVerifier.create(service.leaveBotDraughtsRoom(roomId, hostId))
                .expectNext(true).verifyComplete();

        verify(games).forfeitBotDraughtsRoom(roomId, hostId);
        verify(botRuntimes).stopRoom(roomId);
        verify(runtimes).remove(roomId);
    }

    @Test
    void leaveBotDraughtsRoom_endsAnOldGameWhoseRuntimeWasLost() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID agentId = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "draughts", 0, null, Instant.now());
        UserRow agent = new UserRow(agentId, "Agent", null, null, null, "agent", false, null,
                true, hostId, "all", "easy", null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, agentId, "Agent")));
        when(users.findById(agentId)).thenReturn(Mono.just(agent));
        when(games.forfeitBotDraughtsRoom(roomId, hostId)).thenReturn(Mono.just(false));
        when(rooms.save(room.withStatus("ended"))).thenReturn(Mono.just(room.withStatus("ended")));
        when(runtimes.find(roomId)).thenReturn(Optional.empty());

        StepVerifier.create(service.leaveBotDraughtsRoom(roomId, hostId))
                .expectNext(true).verifyComplete();

        verify(rooms).save(room.withStatus("ended"));
        verify(botRuntimes).stopRoom(roomId);
    }

    @Test
    void leaveBotDraughtsRoom_keepsHumanMatchAvailableToRejoin() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID opponentId = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "draughts", 0, null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, opponentId, null)));
        when(users.findById(opponentId)).thenReturn(Mono.just(realUser(opponentId)));

        StepVerifier.create(service.leaveBotDraughtsRoom(roomId, hostId))
                .expectNext(false).verifyComplete();

        verifyNoInteractions(games, botRuntimes);
    }

    @Test
    void leaveBotWhotRoom_endsTableWithOnlyOwnedAgents() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID firstAgent = UUID.randomUUID();
        UUID secondAgent = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "whot", 0, null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null),
                RoomMemberRow.of(roomId, firstAgent, "Agent 1"),
                RoomMemberRow.of(roomId, secondAgent, "Agent 2")));
        when(users.findById(firstAgent)).thenReturn(Mono.just(new UserRow(firstAgent, "Agent 1", null,
                null, null, "agent1", false, null, true, hostId, "all", "easy", null, Instant.now())));
        when(users.findById(secondAgent)).thenReturn(Mono.just(new UserRow(secondAgent, "Agent 2", null,
                null, null, "agent2", false, null, true, hostId, "all", "easy", null, Instant.now())));
        when(games.forfeitBotWhotRoom(roomId, hostId)).thenReturn(Mono.just(true));
        when(runtimes.find(roomId)).thenReturn(Optional.empty());

        StepVerifier.create(service.leaveBotWhotRoom(roomId, hostId))
                .expectNext(true).verifyComplete();

        verify(games).forfeitBotWhotRoom(roomId, hostId);
        verify(botRuntimes).stopRoom(roomId);
    }

    @Test
    void leaveBotWhotRoom_keepsTableWithHumanOpponent() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID humanId = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "whot", 0, null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, humanId, null)));
        when(users.findById(humanId)).thenReturn(Mono.just(realUser(humanId)));

        StepVerifier.create(service.leaveBotWhotRoom(roomId, hostId))
                .expectNext(false).verifyComplete();

        verifyNoInteractions(games, botRuntimes);
    }

    @Test
    void leaveBotWhotRoom_releasesAgentFromOldRuntimeLostRoom() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID agentId = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "whot", 0, null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, agentId, "Agent")));
        when(users.findById(agentId)).thenReturn(Mono.just(new UserRow(agentId, "Agent", null,
                null, null, "agent", false, null, true, hostId, "all", "easy", null, Instant.now())));
        when(games.forfeitBotWhotRoom(roomId, hostId)).thenReturn(Mono.just(false));
        when(rooms.save(room.withStatus("ended"))).thenReturn(Mono.just(room.withStatus("ended")));
        when(runtimes.find(roomId)).thenReturn(Optional.empty());

        StepVerifier.create(service.leaveBotWhotRoom(roomId, hostId))
                .expectNext(true).verifyComplete();

        verify(rooms).save(room.withStatus("ended"));
        verify(botRuntimes).stopRoom(roomId);
    }

    @Test
    void leaveBotGoosiRoom_endsTableWithOwnedAgent() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID agentId = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "goosi", 0, null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, agentId, "Agent")));
        when(users.findById(agentId)).thenReturn(Mono.just(new UserRow(agentId, "Agent", null,
                null, null, "agent", false, null, true, hostId, "all", "easy", null, Instant.now())));
        when(games.forfeitBotGoosiRoom(roomId, hostId)).thenReturn(Mono.just(true));
        when(runtimes.find(roomId)).thenReturn(Optional.empty());

        StepVerifier.create(service.leaveBotGoosiRoom(roomId, hostId))
                .expectNext(true).verifyComplete();

        verify(games).forfeitBotGoosiRoom(roomId, hostId);
        verify(botRuntimes).stopRoom(roomId);
    }

    @Test
    void leaveBotGoosiRoom_keepsTableWithHumanOpponent() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID humanId = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "goosi", 0, null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, humanId, null)));
        when(users.findById(humanId)).thenReturn(Mono.just(realUser(humanId)));

        StepVerifier.create(service.leaveBotGoosiRoom(roomId, hostId))
                .expectNext(false).verifyComplete();

        verifyNoInteractions(games, botRuntimes);
    }

    @Test
    void leaveBotWordBluffRoom_endsTableWithOwnedAgent() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID agentId = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "wordbluff", 0, null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, agentId, "Agent")));
        when(users.findById(agentId)).thenReturn(Mono.just(new UserRow(agentId, "Agent", null,
                null, null, "agent", false, null, true, hostId, "all", "easy", null, Instant.now())));
        when(games.forfeitBotWordBluffRoom(roomId, hostId)).thenReturn(Mono.just(true));
        when(runtimes.find(roomId)).thenReturn(Optional.empty());

        StepVerifier.create(service.leaveBotWordBluffRoom(roomId, hostId))
                .expectNext(true).verifyComplete();

        verify(games).forfeitBotWordBluffRoom(roomId, hostId);
        verify(botRuntimes).stopRoom(roomId);
    }

    @Test
    void leaveBotWordBluffRoom_keepsTableWithHumanOpponent() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID humanId = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "wordbluff", 0, null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, humanId, null)));
        when(users.findById(humanId)).thenReturn(Mono.just(realUser(humanId)));

        StepVerifier.create(service.leaveBotWordBluffRoom(roomId, hostId))
                .expectNext(false).verifyComplete();

        verifyNoInteractions(games, botRuntimes);
    }

    @Test
    void leaveBotLudoRoom_closesThreeSeatTableAfterHostForfeits() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        UUID firstAgent = UUID.randomUUID();
        UUID secondAgent = UUID.randomUUID();
        RoomRow room = new RoomRow(roomId, "ABCDEF", null, hostId, "in_game", "ludo", 0, null, Instant.now());
        when(rooms.findById(roomId)).thenReturn(Mono.just(room));
        when(members.findByRoomId(roomId)).thenReturn(Flux.just(
                RoomMemberRow.of(roomId, hostId, null), RoomMemberRow.of(roomId, firstAgent, "A"),
                RoomMemberRow.of(roomId, secondAgent, "B")));
        when(users.findById(firstAgent)).thenReturn(Mono.just(new UserRow(firstAgent, "A", null,
                null, null, "agent-a", false, null, true, hostId, "all", "easy", null, Instant.now())));
        when(users.findById(secondAgent)).thenReturn(Mono.just(new UserRow(secondAgent, "B", null,
                null, null, "agent-b", false, null, true, hostId, "all", "easy", null, Instant.now())));
        when(games.forfeitLudoRoom(roomId, hostId)).thenReturn(Mono.just(true));
        RoomRuntime runtime = mock(RoomRuntime.class);
        when(runtime.state()).thenReturn(new app.truearena.game.ludo.LudoModule().initialState(
                List.of(hostId.toString(), firstAgent.toString(), secondAgent.toString()),
                app.truearena.game.ludo.LudoConfig.defaults(), app.truearena.engine.RandomSource.seeded(1)));
        when(runtimes.find(roomId)).thenReturn(Optional.of(runtime));
        when(rooms.save(room.withStatus("ended"))).thenReturn(Mono.just(room.withStatus("ended")));

        StepVerifier.create(service.leaveBotLudoRoom(roomId, hostId)).expectNext(true).verifyComplete();
        verify(rooms).save(room.withStatus("ended"));
        verify(botRuntimes).stopRoom(roomId);
    }

    @Test
    void abandon_isBlockedOnceTheGameHasStarted() {
        UUID roomId = UUID.randomUUID();
        UUID hostId = UUID.randomUUID();
        when(rooms.findById(roomId)).thenReturn(Mono.just(room(roomId, hostId, 0)));
        RoomRuntime rt = new RoomRuntime(roomId, hostId.toString());
        rt.start(new app.truearena.game.whot.WhotModule(),
                new app.truearena.game.whot.WhotModule().initialState(List.of("a", "b"),
                        app.truearena.game.whot.WhotConfig.defaults(), app.truearena.engine.RandomSource.seeded(1)),
                UUID.randomUUID());
        when(runtimes.find(roomId)).thenReturn(Optional.of(rt));

        StepVerifier.create(service.abandon(roomId, hostId))
                .expectErrorMatches(e -> e instanceof ResponseStatusException rse && rse.getStatusCode().value() == 409)
                .verify();

        verify(rooms, never()).deleteById(any(UUID.class));
    }

    // ---------------------------------------------------------------- discoverable

    @Test
    void discoverable_onlyListsStartedRoomsHostedByAnAcceptedFriend() {
        UUID self = UUID.randomUUID();
        UUID friend = UUID.randomUUID();
        UUID stranger = UUID.randomUUID();
        UUID low = FriendRow.lowerOf(self, friend);
        UUID high = low.equals(self) ? friend : self;
        when(friends.findByLowUserIdOrHighUserId(self, self)).thenReturn(Flux.just(
                new FriendRow(UUID.randomUUID(), low, high, FriendRow.ACCEPTED, self, Instant.now())));

        RoomRuntime friendsStartedRoom = new RoomRuntime(UUID.randomUUID(), friend.toString());
        friendsStartedRoom.start(new app.truearena.game.whot.WhotModule(),
                new app.truearena.game.whot.WhotModule().initialState(List.of("a", "b"),
                        app.truearena.game.whot.WhotConfig.defaults(), app.truearena.engine.RandomSource.seeded(1)),
                UUID.randomUUID());
        RoomRuntime friendsLobbyRoom = new RoomRuntime(UUID.randomUUID(), friend.toString()); // not started
        RoomRuntime strangersStartedRoom = new RoomRuntime(UUID.randomUUID(), stranger.toString());
        strangersStartedRoom.start(new app.truearena.game.whot.WhotModule(),
                new app.truearena.game.whot.WhotModule().initialState(List.of("a", "b"),
                        app.truearena.game.whot.WhotConfig.defaults(), app.truearena.engine.RandomSource.seeded(1)),
                UUID.randomUUID());
        when(runtimes.all()).thenReturn(List.of(friendsStartedRoom, friendsLobbyRoom, strangersStartedRoom));
        when(rooms.findById(friendsStartedRoom.roomId)).thenReturn(Mono.just(room(friendsStartedRoom.roomId, friend, 0)));
        when(users.findById(friend)).thenReturn(Mono.just(realUser(friend)));

        StepVerifier.create(service.discoverable(self))
                .expectNextMatches(v -> v.roomId().equals(friendsStartedRoom.roomId))
                .verifyComplete();
    }
}
