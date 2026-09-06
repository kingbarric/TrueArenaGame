rootProject.name = "truearena-backend"

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}

include(
    "ta-app",
    "ta-api",
    "ta-ws",
    "ta-engine",
    "ta-game-truearena",
    "ta-room",
    "ta-voice",
    "ta-persistence",
    "ta-contract-tests",
)
