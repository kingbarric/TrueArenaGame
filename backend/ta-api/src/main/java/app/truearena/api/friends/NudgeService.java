package app.truearena.api.friends;

import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.push.PushNotificationService;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.FriendRepository;
import app.truearena.persistence.FriendRow;
import app.truearena.persistence.UserRepository;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * "Come online!" — a tap next to a friend's name that buzzes their phone.
 *
 * <p>If they have the app open it vibrates and shows who nudged them right
 * away; if not, it arrives as a push notification (which also lands on their
 * Notifications page). One nudge per friend every {@link #COOLDOWN}, so it
 * stays a nudge and not a way to make someone's phone buzz nonstop.
 */
@Service
public class NudgeService {

    static final Duration COOLDOWN = Duration.ofSeconds(30);

    private final FriendRepository friends;
    private final UserRepository users;
    private final InboxRegistry inbox;
    private final PushNotificationService push;
    private final Clock clock;
    private final Map<String, Instant> lastNudge = new ConcurrentHashMap<>();

    public NudgeService(FriendRepository friends, UserRepository users, InboxRegistry inbox,
                        PushNotificationService push) {
        this(friends, users, inbox, push, Clock.systemUTC());
    }

    NudgeService(FriendRepository friends, UserRepository users, InboxRegistry inbox,
                 PushNotificationService push, Clock clock) {
        this.friends = friends;
        this.users = users;
        this.inbox = inbox;
        this.push = push;
        this.clock = clock;
    }

    public Mono<Void> nudge(UUID fromId, UUID toId) {
        if (fromId.equals(toId)) {
            return Mono.error(ApiExceptions.badRequest("you can't nudge yourself"));
        }
        UUID low = FriendRow.lowerOf(fromId, toId);
        UUID high = low.equals(fromId) ? toId : fromId;
        return friends.findByLowUserIdAndHighUserId(low, high)
                .filter(row -> FriendRow.ACCEPTED.equals(row.status()))
                .switchIfEmpty(Mono.error(ApiExceptions.forbidden("you can only nudge a friend")))
                .then(Mono.defer(() -> {
                    String key = fromId + ">" + toId;
                    Instant now = clock.instant();
                    Instant last = lastNudge.get(key);
                    if (last != null && last.plus(COOLDOWN).isAfter(now)) {
                        return Mono.error(ApiExceptions.conflict("you just nudged them — give it a moment"));
                    }
                    lastNudge.put(key, now);
                    return users.findById(fromId);
                }))
                .switchIfEmpty(Mono.error(ApiExceptions.notFound("no such user")))
                .doOnNext(from -> {
                    String name = from.displayName();
                    Map<String, String> data = Map.of("type", "NUDGE", "fromId", fromId.toString(), "fromName", name);
                    inbox.notify(toId, Map.of("type", "NUDGE", "data", data));
                    push.sendToUserIfOffline(toId, name + " nudged you 👋", "Come online and play!", data);
                })
                .then();
    }
}
