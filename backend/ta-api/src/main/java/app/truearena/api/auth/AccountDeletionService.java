package app.truearena.api.auth;

import app.truearena.api.inbox.InboxRegistry;
import app.truearena.api.support.ApiExceptions;
import app.truearena.persistence.AppleAccountRepository;
import app.truearena.persistence.UserRepository;
import app.truearena.room.RoomLock;
import app.truearena.room.RoomRuntimeRegistry;
import app.truearena.voice.LiveKitRoomAdmin;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.List;
import java.util.UUID;
import java.util.function.Supplier;

@Service
public class AccountDeletionService {
    private final DatabaseClient db;
    private final UserRepository users;
    private final AppleAccountRepository appleAccounts;
    private final AppleAuthService appleAuth;
    private final AppleTokenRevocation appleRevocation;
    private final AccountSessionGuard sessions;
    private final RoomRuntimeRegistry runtimes;
    private final RoomLock locks;
    private final InboxRegistry inbox;
    private final LiveKitRoomAdmin voice;
    private final OtpService otp;

    public AccountDeletionService(DatabaseClient db, UserRepository users, AppleAccountRepository appleAccounts,
            AppleAuthService appleAuth, AppleTokenRevocation appleRevocation, AccountSessionGuard sessions,
            RoomRuntimeRegistry runtimes, RoomLock locks, InboxRegistry inbox, LiveKitRoomAdmin voice, OtpService otp) {
        this.db=db; this.users=users; this.appleAccounts=appleAccounts; this.appleAuth=appleAuth;
        this.appleRevocation=appleRevocation; this.sessions=sessions; this.runtimes=runtimes;
        this.locks=locks; this.inbox=inbox; this.voice=voice;
        this.otp=otp;
    }

    public record Requirements(boolean appleLinked, boolean appleRevocationReady) {}
    public record Confirmation(boolean confirmed, String appleIdToken, String appleNonce, String appleAuthorizationCode) {}

    public Mono<Requirements> requirements(UUID user) {
        return users.findById(user).filter(u -> !u.isBot())
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("account unavailable")))
                .flatMap(ignored -> appleAccounts.findByUserId(user).hasElement())
                .map(linked -> new Requirements(linked, appleRevocation.configured()));
    }

    public Mono<Void> delete(UUID user, Confirmation confirmation) {
        if (!confirmation.confirmed()) return Mono.error(ApiExceptions.badRequest("Confirm account deletion"));
        return requirements(user)
                .flatMap(required -> !required.appleLinked() ? Mono.<Void>empty()
                        : revokeApple(user, confirmation))
                .then(users.findById(user).flatMap(row -> otp.forget(row.email(),row.phone())))
                .then(db.sql("SELECT DISTINCT r.id FROM rooms r LEFT JOIN room_members m ON m.room_id=r.id "
                        + "WHERE r.host_id=:u OR m.user_id=:u ORDER BY r.id")
                        .bind("u", user).map((r,m) -> r.get("id",UUID.class)).all().collectList())
                .flatMap(rooms -> withLocks(rooms.stream().filter(id -> runtimes.find(id).isPresent()).toList(),0,
                        () -> erase(user).doOnSuccess(ignored -> retire(rooms))))
                .then(sessions.close(user))
                .doOnSuccess(ignored -> inbox.erase(user));
    }

    private Mono<Void> revokeApple(UUID user, Confirmation c) {
        return appleAccounts.findByUserId(user).flatMap(link -> appleAuth.verify(c.appleIdToken(), c.appleNonce())
                .filter(identity -> identity.subject().equals(link.subject()))
                .switchIfEmpty(Mono.error(ApiExceptions.unauthorized("Use the Apple account linked to this player")))
                .flatMap(ignored -> appleRevocation.revoke(c.appleAuthorizationCode(),link.subject())));
    }

    private Mono<Void> erase(UUID user) {
        // Remove live media access before erasing participant rows. A failed media
        // operation aborts deletion so it can be retried without losing that index.
        return db.sql("SELECT DISTINCT room_name FROM voice_sessions s JOIN voice_session_participants p "
                        + "ON p.voice_session_id=s.id WHERE p.user_id=:u AND p.left_at IS NULL")
                .bind("u",user).map((r,m) -> r.get("room_name",String.class)).all()
                .concatMap(room -> voice.remove(room,user.toString()))
                .then(db.sql("SELECT erase_playhuud_account(:u) AS erased").bind("u",user)
                        .map((r,m) -> Boolean.TRUE.equals(r.get("erased",Boolean.class))).one())
                .flatMap(erased -> erased ? Mono.empty() : Mono.error(ApiExceptions.unauthorized("account unavailable")));
    }

    private Mono<Void> withLocks(List<UUID> rooms, int index, Supplier<Mono<Void>> work) {
        return index == rooms.size() ? Mono.defer(work)
                : locks.withLock(rooms.get(index), Duration.ofSeconds(30), () -> withLocks(rooms,index+1,work));
    }

    private void retire(List<UUID> rooms) {
        rooms.forEach(id -> runtimes.find(id).ifPresent(rt -> {
            rt.retired=true; rt.paused=true; rt.cancelTimer();
            rt.unicast.values().forEach(s -> s.tryEmitComplete());
            rt.bus.tryEmitComplete();
            runtimes.remove(id);
        }));
    }
}
