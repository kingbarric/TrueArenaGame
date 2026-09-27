package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Goosi's bot adapter — mirrors {@code DraughtsBotAdapter}'s shape closely
 * (tracks pit counts + ownership from raw events, same PHASE-frame ordering
 * discipline — see that class's doc for why a bare PHASE frame is never
 * enough to decide a move on its own).
 */
public final class GoosiBotAdapter implements GameBotAdapter {

    private static final SecureRandom RNG = new SecureRandom();
    private static final Pattern PIT_JSON = Pattern.compile("\"pit\"\\s*:\\s*(\\d+)");

    private final int[] pits = new int[16];
    private final String[] owner = new String[16];
    private final List<String> players = new ArrayList<>();
    private String phase = "TurnP0";
    private boolean finished;

    @Override
    public String gameType() {
        return "goosi";
    }

    @Override
    @SuppressWarnings("unchecked")
    public Optional<BotPrompt> onFrame(String frameType, Map<String, Object> payload, String botUserId, Difficulty difficulty) {
        switch (frameType) {
            case "SNAPSHOT" -> applySnapshot(payload);
            case "EVENT" -> applyEvent((Map<String, Object>) payload.getOrDefault("data", Map.of()),
                    String.valueOf(payload.get("type")));
            // Same discipline as DraughtsBotAdapter: a bare PHASE frame arrives
            // before the domain EVENTs describing what changed — never decide
            // a move off it directly, only track the phase name.
            case "PHASE" -> {
                phase = String.valueOf(payload.get("phase"));
                return Optional.empty();
            }
            default -> { /* ERROR and anything else: nothing to update here */ }
        }
        if (finished || players.isEmpty()) {
            return Optional.empty();
        }
        int myIndex = players.indexOf(botUserId);
        if (myIndex < 0 || !("TurnP" + myIndex).equals(phase)) {
            return Optional.empty();
        }
        if (legalPits(botUserId).isEmpty()) {
            return Optional.empty();
        }
        return Optional.of(buildPrompt(botUserId, difficulty));
    }

    @SuppressWarnings("unchecked")
    private void applySnapshot(Map<String, Object> p) {
        Object ph = p.get("phase");
        if (ph != null) phase = String.valueOf(ph);
        Object pl = p.get("players");
        if (pl instanceof List<?> list) {
            players.clear();
            for (Object o : list) players.add(String.valueOf(o));
        }
        Object own = p.get("owner");
        if (own instanceof List<?> list) applyOwnerSnapshot((List<Object>) list);
        Object rawPits = p.get("pits");
        if (rawPits instanceof List<?> list) applyPitsSnapshot((List<Object>) list);
    }

    private void applyOwnerSnapshot(List<Object> raw) {
        for (int i = 0; i < 16 && i < raw.size(); i++) {
            owner[i] = raw.get(i) == null ? null : String.valueOf(raw.get(i));
        }
    }

    private void applyPitsSnapshot(List<Object> raw) {
        for (int i = 0; i < 16 && i < raw.size(); i++) {
            pits[i] = intOf(raw.get(i));
        }
    }

    @SuppressWarnings("unchecked")
    private void applyEvent(Map<String, Object> data, String type) {
        switch (type) {
            case "GAME_STARTED" -> {
                players.clear();
                Object pl = data.get("players");
                if (pl instanceof List<?> list) for (Object o : list) players.add(String.valueOf(o));
                Object own = data.get("owner");
                if (own instanceof List<?> list) applyOwnerSnapshot((List<Object>) list);
                Object rawPits = data.get("pits");
                if (rawPits instanceof List<?> list) applyPitsSnapshot((List<Object>) list);
            }
            case "SOWN" -> {
                int from = intOf(data.get("from"));
                Object touchedRaw = data.get("touched");
                pits[from] = 0;
                if (touchedRaw instanceof List<?> touched) {
                    for (Object o : touched) pits[intOf(o)]++;
                }
            }
            case "CAPTURED" -> {
                int pit = intOf(data.get("pit"));
                int opp = intOf(data.get("opposite"));
                pits[pit] = 0;
                pits[opp] = 0;
            }
            case "GAME_OVER" -> finished = true;
            default -> { /* TURN_STARTED carries nothing this bot needs beyond the PHASE frame */ }
        }
    }

    private static int intOf(Object o) {
        return o instanceof Number n ? n.intValue() : Integer.parseInt(String.valueOf(o));
    }

    private List<Integer> legalPits(String botUserId) {
        List<Integer> out = new ArrayList<>();
        for (int i = 0; i < 16; i++) {
            if (botUserId.equals(owner[i]) && pits[i] > 0) out.add(i);
        }
        return out;
    }

    private BotPrompt buildPrompt(String botUserId, Difficulty difficulty) {
        List<Integer> legal = legalPits(botUserId);
        StringBuilder board = new StringBuilder();
        for (int i = 0; i < 16; i++) {
            board.append(i).append(':').append(pits[i]).append(owner[i].equals(botUserId) ? "(you) " : " ");
        }
        String system = """
                You are playing Goosi, a 16-pit sowing/capture board game (Mancala family). \
                Sowing a pit drops one seed into each following pit going around the ring. \
                If your very last seed lands in one of your own pits that was empty, you \
                capture that seed plus everything in the opposite pit (index+8 mod 16).
                %s
                Reply with ONLY a JSON object of the exact shape {"pit": <index>} naming one \
                of your legal pits — no other text.""".formatted(
                switch (difficulty) {
                    case EASY -> "Play a reasonable pit.";
                    case MEDIUM -> "Prefer moves that land your last seed in one of your own empty pits — that's a capture.";
                    case HARD -> "Think ahead: prioritize captures, avoid leaving a pit at a count that lets the opponent "
                            + "capture it next turn, and try to keep seeds moving toward your own side.";
                });
        String user = "Board: " + board + ". Your legal pits: " + legal;
        return new BotPrompt(system, user);
    }

    @Override
    public Optional<PlayerAction> parseAction(String rawResponse, String botUserId) {
        if (rawResponse == null || rawResponse.isBlank()) {
            return Optional.empty();
        }
        Matcher m = PIT_JSON.matcher(rawResponse);
        if (!m.find()) {
            return Optional.empty();
        }
        int pit = Integer.parseInt(m.group(1));
        if (!legalPits(botUserId).contains(pit)) {
            return Optional.empty();
        }
        return Optional.of(PlayerAction.of(botUserId, "SOW", Map.of("pit", pit)));
    }

    @Override
    public Optional<PlayerAction> fallbackAction(String botUserId) {
        List<Integer> legal = legalPits(botUserId);
        if (legal.isEmpty()) {
            return Optional.empty();
        }
        int pit = legal.get(RNG.nextInt(legal.size()));
        return Optional.of(PlayerAction.of(botUserId, "SOW", Map.of("pit", pit)));
    }
}
