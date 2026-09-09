package app.truearena.api.game;

import app.truearena.engine.GameConfig;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

@Component
public class GameJson {

    private final ObjectMapper mapper;

    public GameJson(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    public String write(Object value) {
        try {
            return mapper.writeValueAsString(value);
        } catch (Exception e) {
            throw new IllegalStateException("cannot serialize config", e);
        }
    }

    public GameConfig readConfig(String json) {
        try {
            return mapper.readValue(json, GameConfig.class);
        } catch (Exception e) {
            throw new IllegalArgumentException("invalid GameConfig JSON: " + e.getMessage(), e);
        }
    }

    public GameConfig readConfig(Object tree) {
        return mapper.convertValue(tree, GameConfig.class);
    }
}
