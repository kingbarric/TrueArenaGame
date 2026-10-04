package app.truearena.api.bot;

import app.truearena.api.bot.BotDtos.BotAddedView;
import app.truearena.api.bot.BotDtos.RenameAgentRequest;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

/** Compatibility surface for app versions that still request a saved-agent roster. */
@RestController
@RequestMapping("/api/v1/agents")
@Tag(name = "bots", description = "AI agents that join a room as a real player — see docs/DEV_REFERENCE.md.")
public class AgentController {

    private final BotService bots;

    public AgentController(BotService bots) {
        this.bots = bots;
    }

    @GetMapping
    @Operation(summary = "Deprecated: returns an empty saved-agent roster")
    public Flux<BotAddedView> list(@RequestParam String gameType) {
        return CurrentUser.id().flatMapMany(userId -> bots.listAgents(userId, gameType));
    }

    @DeleteMapping("/{agentId}")
    @Operation(summary = "Deprecated: saved Cyber Agents are no longer managed")
    public Mono<Void> delete(@PathVariable UUID agentId) {
        return CurrentUser.id().flatMap(userId -> bots.deleteAgent(agentId, userId));
    }

    @PatchMapping("/{agentId}")
    @Operation(summary = "Deprecated: names are selected when adding an agent to a Huud")
    public Mono<BotAddedView> rename(@PathVariable UUID agentId, @Valid @RequestBody RenameAgentRequest body) {
        return CurrentUser.id().flatMap(userId -> bots.rename(agentId, userId, body.name()));
    }
}
