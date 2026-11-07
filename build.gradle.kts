plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.compose) apply false
}

group = "com.github.hussain-najeb"
version = libs.versions.appversion.get()

