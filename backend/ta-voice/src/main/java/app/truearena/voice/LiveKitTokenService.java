package app.truearena.voice;

import io.livekit.server.AccessToken;
import io.livekit.server.CanPublish;
import io.livekit.server.CanPublishData;
import io.livekit.server.CanSubscribe;
import io.livekit.server.RoomJoin;
import io.livekit.server.RoomName;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Service;

/**
 * Mints a LiveKit join token for one participant in one room. Nothing here
 * decides *who's allowed* into a given room — that's {@code CallService}
 * (ta-api), which knows about friendships/group membership; this class only
 * knows how to sign a token once that decision's already been made.
 */
@Service
@EnableConfigurationProperties(LiveKitProperties.class)
public class LiveKitTokenService {

    private final LiveKitProperties props;

    public LiveKitTokenService(LiveKitProperties props) {
        this.props = props;
    }

    public String wsUrl() {
        return props.url();
    }

    /** A one-hour token is plenty for a voice call — nobody's staying on one longer than that unnoticed. */
    public String mintToken(String roomName, String participantId, String participantName) {
        return mintToken(roomName, participantId, participantName, true);
    }

    /** Spectator tokens stay listen-only even if reused after a player removes them. */
    public String mintToken(String roomName, String participantId, String participantName, boolean canPublish) {
        return mint(roomName, participantId, participantName, canPublish, true, 60 * 60 * 1000L);
    }

    /** A short-lived, receive-only credential for a live Huud preview. */
    public String mintPreviewToken(String roomName, String participantId, String participantName) {
        return mint(roomName, participantId, participantName, false, false, 60 * 1000L);
    }

    private String mint(String roomName, String participantId, String participantName,
                        boolean canPublish, boolean canPublishData, long ttl) {
        AccessToken token = new AccessToken(props.apiKey(), props.apiSecret());
        token.setIdentity(participantId);
        token.setName(participantName);
        token.setTtl(ttl);
        token.addGrants(
                new RoomJoin(true),
                new RoomName(roomName),
                new CanPublish(canPublish),
                new CanPublishData(canPublishData),
                new CanSubscribe(true)
        );
        return token.toJwt();
    }
}
