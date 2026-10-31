plugins {
    `kotlin-dsl`
    id("signing")
    id("maven-publish")
}

repositories {
    mavenCentral()
    google()
}

dependencies {
    implementation(libs.android.gradle.plugin)
    implementation(gradleApi())
    implementation(localGroovy())
}

gradlePlugin {
    plugins {
        create("PublishPlugin") {
            id = "com.yausername.youtubedl_android"
            implementationClass = "com.yausername.youtubedl_android.PublishPlugin"
        }
    }
}

kotlin {
    jvmToolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}
