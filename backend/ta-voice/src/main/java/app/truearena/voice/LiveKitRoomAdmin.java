package app.truearena.voice;

import io.livekit.server.RoomServiceClient;
import livekit.LivekitModels.ParticipantPermission;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.io.IOException;

/** Server-side controls for an already-connected game-voice participant. */
@Service
@EnableConfigurationProperties(LiveKitProperties.class)
public class LiveKitRoomAdmin {

    private final RoomServiceClient rooms;

    public LiveKitRoomAdmin(LiveKitProperties props) {
        String httpUrl = props.url().replaceFirst("^ws", "http");
        rooms = RoomServiceClient.create(httpUrl, props.apiKey(), props.apiSecret());
    }

    public Mono<Void> setCanPublish(String roomName, String participantId, boolean canPublish) {
        ParticipantPermission permission = ParticipantPermission.newBuilder()
                .setCanSubscribe(true)
                .setCanPublish(canPublish)
                .setCanPublishData(true)
                .build();
        return Mono.fromCallable(() -> {
                    var response = rooms.updateParticipant(
                            roomName, participantId, "", "", permission).execute();
                    if (!response.isSuccessful()) {
                        throw new IOException("LiveKit update failed with HTTP " + response.code());
                    }
                    return response;
                })
                .subscribeOn(Schedulers.boundedElastic())
                .then();
    }

    public Mono<Void> remove(String roomName, String participantId) {
        return Mono.fromCallable(() -> {
                    var response = rooms.removeParticipant(roomName, participantId).execute();
                    if (!response.isSuccessful() && response.code() != 404) {
                        throw new IOException("LiveKit removal failed with HTTP " + response.code());
                    }
                    return response;
                })
                .subscribeOn(Schedulers.boundedElastic())
                .then();
    }
}
