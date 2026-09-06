description = "LiveKit token minting, webhook consumer, forced mute on Vote phase (Phase 8)."

dependencies {
    api("org.springframework.boot:spring-boot-starter-webflux")
    implementation(project(":ta-room"))
    implementation("io.livekit:livekit-server:0.8.1")
}
