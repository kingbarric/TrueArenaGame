description = "Reactive WebSocket transport, event fan-out, per-subscriber visibility filtering (Phase 4)."

dependencies {
    api("org.springframework.boot:spring-boot-starter-webflux")
    implementation(project(":ta-engine"))
    implementation(project(":ta-room"))
}
