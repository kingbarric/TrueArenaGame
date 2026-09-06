plugins {
    `java-library`
    alias(libs.plugins.spring.boot) apply false
    alias(libs.plugins.spring.dependency.management) apply false
}

val springBootVersion = "3.3.5"
val testcontainersVersion = "1.20.3"

allprojects {
    group = "app.truearena"
    version = "0.0.1-SNAPSHOT"
}

subprojects {
    apply(plugin = "java-library")
    apply(plugin = "io.spring.dependency-management")

    extensions.configure<JavaPluginExtension> {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(21))
        }
    }

    repositories {
        mavenCentral()
    }

    extensions.configure<io.spring.gradle.dependencymanagement.dsl.DependencyManagementExtension> {
        imports {
            mavenBom("org.springframework.boot:spring-boot-dependencies:$springBootVersion")
            mavenBom("org.testcontainers:testcontainers-bom:$testcontainersVersion")
        }
    }

    dependencies {
        "testImplementation"("org.springframework.boot:spring-boot-starter-test")
        "testImplementation"("io.projectreactor:reactor-test")
    }

    tasks.withType<Test>().configureEach {
        useJUnitPlatform()
        testLogging { events("passed", "skipped", "failed") }
    }

    // Slow Testcontainers tests live behind `./gradlew integrationTest`.
    tasks.register<Test>("integrationTest") {
        description = "Runs @Tag(\"integration\") tests (Testcontainers)."
        group = "verification"
        useJUnitPlatform { includeTags("integration") }
        shouldRunAfter(tasks.named("test"))
    }

    tasks.named<Test>("test") {
        useJUnitPlatform { excludeTags("integration") }
    }
}
