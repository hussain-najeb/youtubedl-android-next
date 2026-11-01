plugins {
    id("com.yausername.youtubedl_android")
    id("signing")
    id("com.android.library")
    id("maven-publish")
}

android {
    namespace = "com.yausername.youtubedl_android"
    compileSdk = 34

    defaultConfig {
        minSdk = 24

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

configurePublishing {
    artifactId = project.name
    isPublished = true
}

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))

    implementation(project(":common"))

    implementation(libs.appcompat)
    implementation(libs.core.ktx)
    testImplementation(libs.junit)
    androidTestImplementation(libs.android.junit)
    androidTestImplementation(libs.espresso)

    implementation(libs.jackson.databind)
    implementation(libs.jackson.annotations)
    implementation(libs.commons.io)
    implementation(libs.coroutines.core)
}
