package app.truearena.api.ws;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import app.truearena.engine.*;
import app.truearena.game.monopoly.*;
import app.truearena.room.*;
import app.truearena.ws.contract.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.*;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Sinks;

class MonopolySpectatorTest {
  @Test
  void helloDeliversFullPublicBoardButOnlyOwnPrivateOffers() throws Exception {
    MonopolyModule module = new MonopolyModule();
    RoomRuntime rt = new RoomRuntime(UUID.randomUUID(), "a");
    rt.config = MonopolyConfig.defaults();
    GameState state =
        module.initialState(List.of("a", "b", "c"), rt.config, RandomSource.seeded(4));
    state =
        module.onPlayerAction(
            state,
            PlayerAction.of("a", "OFFER_TRADE", Map.of("to", "b", "giveCash", 20, "takeCash", 0)));
    rt.start(module, state, UUID.randomUUID());
    rt.spectatorUserIds.add("watcher");
    ObjectMapper mapper = new ObjectMapper();
    GameOrchestrator server =
        new GameOrchestrator(
            null,
            null,
            mock(RoomEventLog.class),
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            mapper,
            null);
    for (String user : List.of("a", "b", "c", "watcher")) {
      var sink = Sinks.many().unicast().onBackpressureBuffer();
      rt.unicast.put(user, sink);
      List<Envelope> frames = new ArrayList<>();
      var sub = sink.asFlux().cast(Envelope.class).subscribe(frames::add);
      server
          .handleFrame(
              rt,
              user,
              mapper.writeValueAsString(Envelope.of(MessageType.HELLO, Map.of("lastSeq", 12))),
              user.equals("watcher"))
          .block();
      sub.dispose();
      Envelope snapshot =
          frames.stream().filter(f -> f.type() == MessageType.SNAPSHOT).findFirst().orElseThrow();
      assertThat((List<?>) snapshot.payload().get("board")).hasSize(40);
      assertThat(snapshot.payload()).doesNotContainKeys("seed", "chance", "chest", "rollCount");
      if (Set.of("a", "b").contains(user))
        assertThat((List<?>) snapshot.payload().get("tradeOffers")).hasSize(1);
      else if (user.equals("c"))
        assertThat((List<?>) snapshot.payload().get("tradeOffers")).isEmpty();
      else assertThat(snapshot.payload()).doesNotContainKey("tradeOffers");
      assertThat(frames).extracting(Envelope::type).contains(MessageType.PHASE);
    }
  }
}
