package app.truearena.voice;

import io.livekit.server.RoomServiceClient;
import livekit.LivekitModels.ParticipantInfo;
import livekit.LivekitModels.ParticipantPermission;
import livekit.LivekitModels.TrackType;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.io.IOException;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/** Server-side controls for participants already connected to a voice room. */
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

    /** Who is connected to a room right now (their identities). Empty if the room doesn't exist. */
    public Mono<Set<String>> participantIds(String roomName) {
        return listParticipants(roomName)
                .map(list -> list.stream().map(ParticipantInfo::getIdentity).collect(Collectors.toSet()));
    }

    /** Server-side mute of everything a participant is publishing as audio. They can unmute themselves. */
    public Mono<Void> muteAudio(String roomName, String participantId) {
        return listParticipants(roomName)
                .flatMap(list -> Mono.fromCallable(() -> {
                    for (ParticipantInfo p : list) {
                        if (!p.getIdentity().equals(participantId)) continue;
                        for (var track : p.getTracksList()) {
                            if (track.getType() != TrackType.AUDIO || track.getMuted()) continue;
                            var response = rooms.mutePublishedTrack(roomName, participantId, track.getSid(), true).execute();
                            if (!response.isSuccessful()) {
                                throw new IOException("LiveKit mute failed with HTTP " + response.code());
                            }
                        }
                    }
                    return true;
                }).subscribeOn(Schedulers.boundedElastic()))
                .then();
    }

    private Mono<List<ParticipantInfo>> listParticipants(String roomName) {
        return Mono.fromCallable(() -> {
                    var response = rooms.listParticipants(roomName).execute();
                    if (response.code() == 404) {
                        return List.<ParticipantInfo>of();
                    }
                    if (!response.isSuccessful() || response.body() == null) {
                        throw new IOException("LiveKit list failed with HTTP " + response.code());
                    }
                    return response.body();
                })
                .subscribeOn(Schedulers.boundedElastic());
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
