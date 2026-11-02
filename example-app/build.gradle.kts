plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
}

kotlin {
    compilerOptions {
        freeCompilerArgs.add("-opt-in=androidx.compose.material3.ExperimentalMaterial3ExpressiveApi")
    }
}

android {
    buildFeatures {
        compose = true
    }

    namespace = "org.foss.youtube.next.example"
    compileSdk = 37

    defaultConfig {
        applicationId = "org.foss.youtube.next.example"
        minSdk = 24
        //noinspection EditedTargetSdkVersion
        targetSdk = 37
        versionName = libs.versions.appversion.get()
        versionCode = libs.versions.appversioncode.get().toInt()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters.add("x86")
            abiFilters.add("x86_64")
            abiFilters.add("armeabi-v7a")
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    splits.abi {
        isEnable = true
        reset()
        include("x86", "x86_64", "armeabi-v7a", "arm64-v8a")
        isUniversalApk = true
    }
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

}

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))

    implementation(project(":main-lib"))

    implementation(platform(libs.compose.bom))
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.runtime.ktx)
    implementation(libs.coil.network.okhttp)
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.work.runtime.ktx)
    implementation(libs.material)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.appcompat)
    implementation(libs.constraintlayout)
    implementation(libs.core.ktx)
    implementation(libs.animated.vector.drawable)
    testImplementation(libs.junit)
    androidTestImplementation(libs.android.junit)
    androidTestImplementation(libs.espresso)

    implementation(libs.rxandroid)
    implementation(libs.exomedia)
}
