plugins {
    alias(libs.plugins.spring.boot)
}

description = "Spring Boot entrypoint: wires every module, exposes actuator, runs Flyway."

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.springframework.boot:spring-boot-starter-webflux")

    implementation(project(":ta-api"))
    implementation(project(":ta-ws"))
    implementation(project(":ta-voice"))
    implementation(project(":ta-room"))
    implementation(project(":ta-persistence"))
    implementation(project(":ta-engine"))
    implementation(project(":ta-game-truearena"))
}

tasks.named<org.springframework.boot.gradle.tasks.bundling.BootJar>("bootJar") {
    archiveFileName.set("truearena-backend.jar")
}
