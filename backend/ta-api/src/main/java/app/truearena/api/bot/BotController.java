package app.truearena.api.bot;

import app.truearena.api.bot.BotDtos.AddBotRequest;
import app.truearena.api.bot.BotDtos.BotAddedView;
import app.truearena.api.support.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/rooms/{roomId}/bots")
@Tag(name = "bots", description = "AI agents that join a room as a real player — see docs/DEV_REFERENCE.md.")
public class BotController {

    private final BotService bots;

    public BotController(BotService bots) {
        this.bots = bots;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Add an AI player to the room (host-only, lobby-only)")
    public Mono<BotAddedView> add(@PathVariable UUID roomId, @Valid @RequestBody AddBotRequest body) {
        return CurrentUser.id().flatMap(hostId -> bots.addBot(roomId, hostId, body.name(), body.difficulty()));
    }

    @PostMapping("/existing/{agentId}")
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Re-hire an agent the caller already created (host-only, lobby-only)")
    public Mono<BotAddedView> addExisting(@PathVariable UUID roomId, @PathVariable UUID agentId) {
        return CurrentUser.id().flatMap(hostId -> bots.addExistingAgent(roomId, hostId, agentId));
    }

    @DeleteMapping("/{botId}")
    @Operation(summary = "Remove an AI player from the room (host-only)")
    public Mono<Void> remove(@PathVariable UUID roomId, @PathVariable UUID botId) {
        return CurrentUser.id().flatMap(hostId -> bots.removeBot(roomId, hostId, botId));
    }
}
