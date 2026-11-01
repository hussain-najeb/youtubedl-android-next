plugins {
    id("com.yausername.youtubedl_android")
    id("signing")
    id("com.android.library")
    id("maven-publish")
}

android {
    namespace = "com.yausername.aria2c"
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
    implementation(libs.core.ktx)
    compileOnly(project(":library"))

    implementation(libs.appcompat)
    testImplementation(libs.junit)
    androidTestImplementation(libs.android.junit)
    androidTestImplementation(libs.espresso)

    implementation(libs.commons.io)
}
