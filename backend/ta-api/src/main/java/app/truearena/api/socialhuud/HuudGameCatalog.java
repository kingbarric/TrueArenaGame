package app.truearena.api.socialhuud;

import app.truearena.engine.*;
import app.truearena.game.draughts.*;
import app.truearena.game.chess.*;
import app.truearena.game.goosi.*;
import app.truearena.game.whot.*;
import app.truearena.game.ludo.*;
import app.truearena.game.wordbluff.*;
import app.truearena.game.truearena.*;
import app.truearena.api.support.ApiExceptions;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import java.util.*;

/** Catalog adapter. Capacities and roster validation are supplied by the game modules. */
@Component
public class HuudGameCatalog {
    private final ObjectMapper mapper;
    public HuudGameCatalog(ObjectMapper mapper) { this.mapper=mapper; }
    public record Entry(GameModule module, GameSettings config) {
        public PlayerCapacity capacity() { return module.playerCapacity(config); }
        public void validate(List<UUID> roster) {
            if (!capacity().accepts(roster.size())) throw ApiExceptions.badRequest("invalid player count for " + module.gameType());
            try { module.initialState(roster.stream().map(UUID::toString).toList(), config, RandomSource.seeded(1)); }
            catch (RuntimeException e) { throw ApiExceptions.badRequest(e.getMessage()); }
        }
    }
    public Entry entry(String type, Map<String,Object> config) {
        try {
            return switch(type) {
                case "draughts" -> new Entry(new DraughtsModule(), merge(DraughtsConfig.defaults(),config,DraughtsConfig.class));
                case "chess" -> new Entry(new ChessModule(),merge(ChessConfig.defaults(),config,ChessConfig.class));
                case "whot" -> new Entry(new WhotModule(),merge(WhotConfig.defaults(),config,WhotConfig.class));
                case "ludo" -> new Entry(new LudoModule(),merge(LudoConfig.defaults(),config,LudoConfig.class));
                case "goosi" -> new Entry(new GoosiModule(),merge(GoosiConfig.defaults(),config,GoosiConfig.class));
                case "wordbluff" -> new Entry(new WordBluffModule(),merge(WordBluffConfig.defaults(),config,WordBluffConfig.class));
                case "truearena" -> new Entry(new TrueArenaModule(),merge(Presets.CLASSIC_CONSPIRACY.config(),config,GameConfig.class));
                default -> throw ApiExceptions.badRequest("unknown Huud game: " + type);
            };
        } catch (org.springframework.web.server.ResponseStatusException e) { throw e; }
        catch (RuntimeException e) { throw ApiExceptions.badRequest("invalid game configuration: " + e.getMessage()); }
    }
    private <T> T merge(T defaults, Map<String,Object> requested, Class<T> type) {
        Map<String,Object> result=new LinkedHashMap<>(mapper.convertValue(defaults,Map.class));
        if (requested != null) result.putAll(requested);
        return mapper.convertValue(result,type);
    }
    public Map<String,Object> config(String type,Map<String,Object> requested) {
        return mapper.convertValue(entry(type,requested).config(),Map.class);
    }
    public SocialHuudDtos.Capacity capacity(String type,Map<String,Object> config) {
        var c=entry(type,config).capacity();
        return new SocialHuudDtos.Capacity(c.min(),c.max(),c.allowed());
    }
    public List<SocialHuudDtos.GameOption> options() {
        return List.of("draughts","whot","chess","ludo","goosi","wordbluff","truearena").stream()
            .map(type->new SocialHuudDtos.GameOption(type,capacity(type,Map.of()))).toList();
    }
}
