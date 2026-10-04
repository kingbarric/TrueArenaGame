package app.truearena.api.push;

import app.truearena.api.support.ApiExceptions;
import app.truearena.api.inbox.InboxRegistry;
import app.truearena.persistence.DeviceTokenRepository;
import app.truearena.persistence.DeviceTokenRow;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.MulticastMessage;
import com.google.firebase.messaging.Notification;
import com.google.firebase.messaging.SendResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * The one place that actually sends an OS push, via Firebase Cloud Messaging
 * (which bridges to APNs for iOS — no separate Apple integration needed here).
 * Fire-and-forget and best-effort throughout, same as {@link InboxRegistry}'s
 * live fan-out and {@code ChampionshipService.tick()} — a push failing (or
 * Firebase not being configured at all, see {@link FirebaseConfig}) must
 * never fail or block whatever triggered it.
 */
@Service
public class PushNotificationService {

    private static final Logger log = LoggerFactory.getLogger(PushNotificationService.class);

    /** FCM's hard cap on tokens per multicast send. */
    private static final int MAX_TOKENS_PER_SEND = 500;

    private final DeviceTokenRepository tokens;
    private final InboxRegistry inbox;
    private final boolean local;

    @Autowired(required = false)
    private FirebaseMessaging messaging;

    public PushNotificationService(DeviceTokenRepository tokens, InboxRegistry inbox, Environment environment) {
        this.tokens = tokens;
        this.inbox = inbox;
        this.local = environment.acceptsProfiles(Profiles.of("local"));
    }

    /** Upserts on the token itself — see the device_tokens migration for why. */
    public Mono<Void> registerToken(UUID userId, String platform, String token) {
        if (!DeviceTokenRow.IOS.equals(platform) && !DeviceTokenRow.ANDROID.equals(platform)) {
            return Mono.error(ApiExceptions.badRequest("platform must be 'ios' or 'android'"));
        }
        return tokens.findByToken(token)
                .flatMap(existing -> tokens.save(existing.reassignedTo(userId)))
                .switchIfEmpty(Mono.defer(() -> tokens.save(DeviceTokenRow.of(userId, platform, token))))
                .then();
    }

    public Mono<Void> unregisterToken(UUID userId, String token) {
        return tokens.deleteByUserIdAndToken(userId, token);
    }

    /** Skips entirely if the recipient has a live inbox socket right now — they already got the in-app event. */
    public void sendToUserIfOffline(UUID userId, String title, String body, Map<String, String> data) {
        if (inbox.isOnline(userId)) return;
        sendToUsers(Set.of(userId), title, body, data);
    }

    /** Unconditional — used for turn reminders (which use room-socket presence, not inbox presence) and broadcasts. */
    public void sendToUsers(Collection<UUID> userIds, String title, String body, Map<String, String> data) {
        if (userIds.isEmpty()) return;
        tokens.findByUserIdIn(userIds)
                .collectList()
                .subscribeOn(Schedulers.boundedElastic())
                .subscribe(rows -> sendTo(rows, title, body, data),
                        e -> log.warn("push lookup failed for {} users: {}", userIds.size(), e.toString()));
    }

    /**
     * Unlike {@link #sendToUsers}, the caller (the admin broadcast scheduler)
     * actually records whether this succeeded, so this reports a real
     * outcome instead of swallowing everything: {@code true} once an actual
     * send was attempted (including the local-dev stub — that's "working as
     * intended", not a failure), {@code false} only when nothing could even
     * be attempted (Firebase unconfigured outside local, or every batch
     * threw before reaching per-token responses). A handful of individual
     * dead tokens inside an otherwise-successful batch don't count as a
     * failure — see the inner loop below, which is unrelated to this result.
     */
    public Mono<Boolean> sendToAll(String title, String body) {
        return tokens.findAll()
                .collectList()
                .map(rows -> sendTo(rows, title, body, Map.of("type", "BROADCAST")));
    }

    private boolean sendTo(List<DeviceTokenRow> rows, String title, String body, Map<String, String> data) {
        if (rows.isEmpty()) return true;
        if (messaging == null) {
            if (local) {
                log.info("[PUSH-STUB] would send \"{}\" / \"{}\" to {} device(s)", title, body, rows.size());
                return true;
            }
            return false; // not configured — nothing was actually attempted
        }
        Notification notification = Notification.builder().setTitle(title).setBody(body).build();
        boolean allBatchesAttempted = true;
        for (int from = 0; from < rows.size(); from += MAX_TOKENS_PER_SEND) {
            List<DeviceTokenRow> chunk = rows.subList(from, Math.min(from + MAX_TOKENS_PER_SEND, rows.size()));
            List<String> chunkTokens = chunk.stream().map(DeviceTokenRow::token).toList();
            MulticastMessage message = MulticastMessage.builder()
                    .addAllTokens(chunkTokens)
                    .setNotification(notification)
                    .putAllData(data)
                    .build();
            try {
                var batch = messaging.sendEachForMulticast(message);
                List<SendResponse> responses = batch.getResponses();
                for (int i = 0; i < responses.size(); i++) {
                    SendResponse response = responses.get(i);
                    if (response.isSuccessful()) continue;
                    FirebaseMessagingException ex = response.getException();
                    MessagingErrorCode code = ex == null ? null : ex.getMessagingErrorCode();
                    if (code == MessagingErrorCode.UNREGISTERED || code == MessagingErrorCode.INVALID_ARGUMENT) {
                        String deadToken = chunkTokens.get(i);
                        tokens.deleteByToken(deadToken).subscribe(null,
                                e -> log.warn("failed to prune dead push token: {}", e.toString()));
                    } else {
                        log.warn("push send failed for one token: {}", ex == null ? "unknown" : ex.toString());
                    }
                }
            } catch (Exception e) {
                log.warn("push send batch failed: {}", e.toString());
                allBatchesAttempted = false; // the batch call itself failed, not just some tokens in it
            }
        }
        return allBatchesAttempted;
    }
}
