// Root project metadata and plugin versions for subprojects.
plugins {
    base
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.ksp) apply false
}

group = "com.github.hussain-najeb"
version = libs.versions.appversion.get()

