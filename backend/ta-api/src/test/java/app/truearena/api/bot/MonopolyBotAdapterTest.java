package app.truearena.api.bot;
import app.truearena.engine.*;
import app.truearena.game.monopoly.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.assertj.core.api.Assertions.*;
class MonopolyBotAdapterTest {
 final ObjectMapper json = new ObjectMapper();
 @SuppressWarnings("unchecked") Map<String,Object> snapshot(MonopolyModule game,GameState state,String id) {
   return json.convertValue(game.visibleStateFor(state,id).data(),Map.class);
 }
 @Test void fullTableKeepsProgressingWithNoModelAndOnlyEngineApprovedActions() {
   MonopolyModule game=new MonopolyModule();
   for(int seed=0; seed<8; seed++) {
     GameState state=game.initialState(List.of("a","b","c","d"),MonopolyConfig.defaults(),RandomSource.seeded(seed));
     Map<String,MonopolyBotAdapter> bots=new HashMap<>();
     for(String id:List.of("a","b","c","d"))bots.put(id,new MonopolyBotAdapter());
     for(int step=0;step<220&&!state.finished();step++) {
       String actor=game.playersToAct(state).iterator().next();
       var bot=bots.get(actor);
       assertThat(bot.onFrame("SNAPSHOT",snapshot(game,state,actor),actor,Difficulty.HARD)).isPresent();
       assertThat(bot.parseAction("{\"index\":99999}",actor)).isEmpty();
       var action=bot.fallbackAction(actor).orElseThrow();
       GameState next=game.onPlayerAction(state,action);
       assertThat(next.round()).isGreaterThan(state.round());
       state=next;
     }
     assertThat(state.events()).hasSizeGreaterThan(100);
   }
 }
 @Test void ignoresOtherTurnsResultsAndInventedChoices() {
   var bot=new MonopolyBotAdapter();
   assertThat(bot.onFrame("SNAPSHOT",Map.of("phase","Roll","decisionPlayer","other","legalActions",List.of(Map.of("action","ROLL","data",Map.of()))),"a",Difficulty.EASY)).isEmpty();
   assertThat(bot.fallbackAction("a")).isEmpty();
   assertThat(bot.onFrame("SNAPSHOT",Map.of("phase","Results"),"a",Difficulty.EASY)).isEmpty();
   assertThat(bot.parseAction("{\"index\":0}","a")).isEmpty();
 }
 @Test void auctionDecisionBelongsToBidderNotTurnOwner() {
   var bot=new MonopolyBotAdapter();
   var choices=List.of(Map.of("action","BID","data",Map.of("amount",10)),Map.of("action","PASS","data",Map.of()));
   assertThat(bot.onFrame("SNAPSHOT",Map.of("phase","Auction","turnPlayer","human","decisionPlayer","agent","legalActions",choices),"agent",Difficulty.MEDIUM)).isPresent();
   assertThat(bot.parseAction("{\"index\":0}","agent").orElseThrow().type()).isEqualTo("BID");
   assertThat(bot.parseAction("{\"index\":0.5}","agent")).isEmpty();
 }
}
