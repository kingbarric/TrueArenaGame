package app.truearena.api.invitation;

import app.truearena.api.championship.ChampionshipService;
import app.truearena.api.huudspace.HuudSpaceService;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.net.URI;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

/** Server-rendered metadata: social crawlers do not need JavaScript or a login. */
@RestController
public class InvitationPageController {
    private final ChampionshipService championships;
    private final HuudSpaceService huuds;
    private final String template, ios, android;
    public InvitationPageController(ChampionshipService championships, HuudSpaceService huuds,
            @Value("${PLAYHUUD_IOS_STORE_URL:}") String ios,
            @Value("${PLAYHUUD_ANDROID_STORE_URL:}") String android) throws IOException {
        this.championships = championships; this.huuds = huuds;
        this.ios = storeUrl(ios, "apps.apple.com"); this.android = storeUrl(android, "play.google.com");
        this.template = new ClassPathResource("invitations/page.html").getContentAsString(StandardCharsets.UTF_8);
    }
    static String storeUrl(String value, String host) {
        if (value == null || value.isBlank()) return "";
        try { URI url = URI.create(value); return "https".equals(url.getScheme()) && host.equals(url.getHost()) && url.getUserInfo() == null ? value : ""; }
        catch (IllegalArgumentException e) { return ""; }
    }
    @GetMapping(value = "/api/v1/invitations/stores", produces = MediaType.APPLICATION_JSON_VALUE)
    public Map<String, String> stores() { return Map.of("ios", ios, "android", android); }

    @GetMapping(value = "/championships/{code}", produces = MediaType.TEXT_HTML_VALUE)
    public Mono<ResponseEntity<String>> championship(@PathVariable String code) {
        if (!code.matches("(?i)[A-HJ-NP-Z2-9]{8}")) return Mono.just(unavailable("championships"));
        return championships.publicInvitation(code).map(c -> page("championships", c.code(), c.name(), c.gameType(),
                "Can you take the crown? Join this " + gameName(c.gameType()) + " championship on PlayHuud. Play as a guest or sign in.", 200))
                .onErrorResume(error -> Mono.just(failure("championships", error)));
    }
    @GetMapping(value = "/huud/{code}", produces = MediaType.TEXT_HTML_VALUE)
    public Mono<ResponseEntity<String>> huud(@PathVariable String code) {
        if (!code.matches("(?i)[A-Z0-9]{6}")) return Mono.just(unavailable("huud"));
        return huuds.invitePreview(code).map(h -> page("huud", h.code(), h.name(), "huud",
                "Good games. Better company. Join " + h.name() + " on PlayHuud. Play as a guest or sign in.", 200))
                .onErrorResume(error -> Mono.just(failure("huud", error)));
    }
    private ResponseEntity<String> failure(String kind, Throwable error) {
        if (error instanceof org.springframework.web.server.ResponseStatusException response && response.getStatusCode().value() == 404)
            return unavailable(kind);
        return page(kind, "", "Invitation temporarily unavailable", "huud",
                "We couldn't load this invitation just now. Please try again shortly.", 503);
    }
    private ResponseEntity<String> unavailable(String kind) {
        return page(kind, "", "Invitation unavailable", "huud", "This invitation is no longer available. Ask the host for a new invitation.", 404);
    }
    ResponseEntity<String> page(String kind, String code, String title, String game, String description, int status) {
        String cover = java.util.Set.of("chess", "draughts", "slayhuud").contains(game) ? game : "huud";
        Map<String, String> values = Map.ofEntries(Map.entry("TITLE", title), Map.entry("DESCRIPTION", description),
                Map.entry("KIND", kind), Map.entry("CODE", code), Map.entry("GAME", gameName(game)),
                Map.entry("URL", "https://playhuud.com/" + kind + "/" + code),
                Map.entry("APP_URL", "playhuud:///" + kind + "/" + code),
                Map.entry("IMAGE", "https://playhuud.com/assets/invite-" + cover + ".png"), Map.entry("IOS", ios), Map.entry("ANDROID", android));
        String html = template;
        for (var e : values.entrySet()) html = html.replace("{{" + e.getKey() + "}}", escape(e.getValue()));
        return ResponseEntity.status(status).contentType(MediaType.TEXT_HTML).header("Cache-Control", "no-store").body(html);
    }
    static String gameName(String game) { return switch (game) { case "chess" -> "Chess"; case "draughts" -> "Draughts"; case "slayhuud" -> "SlayHuud"; default -> "Huud"; }; }
    static String escape(String value) { return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;"); }
}
