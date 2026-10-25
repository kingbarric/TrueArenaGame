package app.truearena.api.huudspace;

import app.truearena.api.inbox.InboxRegistry;
import java.util.Map;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import java.util.UUID;

@Service
public class HuudAvatarService {
    public record Profile(String avatarId, String outfitId, boolean saved, HuudAvatarCatalog.Options catalog) {}
    private final DatabaseClient db;
    private final HuudAvatarCatalog catalog;
    private final InboxRegistry inbox;
    public HuudAvatarService(DatabaseClient db, HuudAvatarCatalog catalog, InboxRegistry inbox) { this.db = db; this.catalog = catalog; this.inbox = inbox; }
    public Mono<Profile> get(UUID user) {
        return db.sql("SELECT avatar_id,outfit_id FROM user_huud_avatars WHERE user_id=:user")
                .bind("user",user).map((r,m) -> new Profile(r.get("avatar_id",String.class),r.get("outfit_id",String.class),true,catalog.options()))
                .one().defaultIfEmpty(new Profile("male","everyday",false,catalog.options()));
    }
    public Mono<Profile> save(UUID user,String avatar,String outfit) {
        catalog.validate(avatar,outfit);
        return db.sql("INSERT INTO user_huud_avatars(user_id,avatar_id,outfit_id) VALUES(:user,:avatar,:outfit) "
                + "ON CONFLICT(user_id) DO UPDATE SET avatar_id=EXCLUDED.avatar_id,outfit_id=EXCLUDED.outfit_id,updated_at=now()")
                .bind("user",user).bind("avatar",avatar).bind("outfit",outfit).fetch().rowsUpdated()
                .thenReturn(new Profile(avatar,outfit,true,catalog.options())).doOnNext(profile -> changed(user));
    }
    private void changed(UUID user) {
        db.sql("SELECT target.huud_space_id,target.user_id FROM huud_space_members mine "
                + "JOIN huud_space_members target ON target.huud_space_id=mine.huud_space_id "
                + "WHERE mine.user_id=:user AND mine.left_at IS NULL AND NOT mine.removed "
                + "AND target.left_at IS NULL AND NOT target.removed")
                .bind("user",user).map((r,m)->Map.entry(r.get("huud_space_id",UUID.class),r.get("user_id",UUID.class))).all()
                .subscribe(pair -> inbox.notify(pair.getValue(),Map.of("type","HUUD_SPACE","data",Map.of(
                        "huudSpaceId",pair.getKey().toString(),"event","avatar-changed","by",user.toString()))),error -> {});
    }

}
