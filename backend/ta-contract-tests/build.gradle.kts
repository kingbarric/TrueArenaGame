description = "Full-session integration tests + the secret-data guarantee (Build Brief §8, Plan 11.5). Also home of the headless bot client."

dependencies {
    testImplementation(project(":ta-app"))
    testImplementation(project(":ta-engine"))
    testImplementation(project(":ta-ws"))
    testImplementation("org.springframework.boot:spring-boot-starter-webflux")
    testImplementation("org.testcontainers:junit-jupiter")
    testImplementation("org.testcontainers:postgresql")
}
