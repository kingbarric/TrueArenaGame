package app.truearena.persistence;

import io.r2dbc.postgresql.codec.Json;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;
import java.util.UUID;

/** A named {@code GameConfig}: the 5 builtin modes, plus group/user saved custom games. */
@Table("game_config_preset")
public record GameConfigPresetRow(
        @Id UUID id,
        String scope,                       // builtin | group | user
        @Column("owner_group_id") UUID ownerGroupId,
        @Column("owner_user_id") UUID ownerUserId,
        String slug,
        String name,
        String description,
        String tag,
        Json config,
        @Column("catalog_version") int catalogVersion,
        @Column("created_at") Instant createdAt
) {

    public String configJson() {
        return config == null ? null : config.asString();
    }

    public static GameConfigPresetRow builtin(String slug, String name, String tag, String description,
                                              String configJson, int catalogVersion) {
        return new GameConfigPresetRow(null, "builtin", null, null, slug, name, description, tag,
                Json.of(configJson), catalogVersion, null);
    }

    public static GameConfigPresetRow forUser(UUID userId, String name, String configJson, int catalogVersion) {
        return new GameConfigPresetRow(null, "user", null, userId, null, name, null, null,
                Json.of(configJson), catalogVersion, null);
    }
}
