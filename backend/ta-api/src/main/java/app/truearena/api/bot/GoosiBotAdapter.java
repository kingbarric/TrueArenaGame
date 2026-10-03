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

    private final int[] pits = new int[12];
    private final String[] owner = new String[12];
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
        for (int i = 0; i < 12 && i < raw.size(); i++) {
            owner[i] = raw.get(i) == null ? null : String.valueOf(raw.get(i));
        }
    }

    private void applyPitsSnapshot(List<Object> raw) {
        for (int i = 0; i < 12 && i < raw.size(); i++) {
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
                Object capturedRaw = data.get("capturedPits");
                if (capturedRaw instanceof List<?> captured) {
                    for (Object o : captured) pits[intOf(o)] = 0;
                }
            }
            case "CAPTURED" -> {
                Object capturedRaw = data.get("pits");
                if (capturedRaw instanceof List<?> captured) {
                    for (Object o : captured) pits[intOf(o)] = 0;
                }
            }
            case "GAME_OVER" -> finished = true;
            default -> { /* TURN_STARTED carries nothing this bot needs beyond the PHASE frame */ }
        }
    }

    private static int intOf(Object o) {
        return o instanceof Number n ? n.intValue() : Integer.parseInt(String.valueOf(o));
    }

    private List<Integer> legalPits(String botUserId) {
        List<Integer> own = new ArrayList<>();
        boolean opponentEmpty = true;
        for (int i = 0; i < 12; i++) {
            if (botUserId.equals(owner[i]) && pits[i] > 0) own.add(i);
            if (!botUserId.equals(owner[i]) && pits[i] > 0) opponentEmpty = false;
        }
        if (!opponentEmpty) return own;
        List<Integer> feeding = new ArrayList<>();
        for (int from : own) {
            int seeds = pits[from];
            int cur = from;
            while (seeds > 0) {
                cur = (cur + 1) % 12;
                if (cur == from) continue;
                if (!botUserId.equals(owner[cur])) {
                    feeding.add(from);
                    break;
                }
                seeds--;
            }
        }
        return feeding;
    }

    private BotPrompt buildPrompt(String botUserId, Difficulty difficulty) {
        List<Integer> legal = legalPits(botUserId);
        StringBuilder board = new StringBuilder();
        for (int i = 0; i < 12; i++) {
            board.append(i).append(':').append(pits[i]).append(owner[i].equals(botUserId) ? "(you) " : " ");
        }
        String system = """
                You are playing Oware Abapa: twelve houses, six per player. \
                Sow every seed counter-clockwise, skipping the starting house on a long lap. \
                If the last seed leaves two or three in an opponent house, capture it and \
                preceding opponent houses that also contain two or three. Feed an empty \
                opponent row whenever possible; a grand slam captures nothing.
                %s
                Reply with ONLY a JSON object of the exact shape {"pit": <index>} naming one \
                of your legal pits — no other text.""".formatted(
                switch (difficulty) {
                    case EASY -> "Play a reasonable pit.";
                    case MEDIUM -> "Prefer legal captures of two or three seeds while preserving future feeding moves.";
                    case HARD -> "Think ahead: prioritize capture chains, avoid giving the opponent a two-or-three capture, "
                            + "and manage feeding without making a void grand slam.";
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
