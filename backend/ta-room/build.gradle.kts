description = "Redis-backed room registry, reconnection tokens, host migration (Phase 3.4 / 4)."

dependencies {
    api(project(":ta-engine"))
    api("org.springframework.boot:spring-boot-starter-data-redis-reactive")
}
