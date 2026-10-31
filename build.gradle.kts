plugins {
    alias(libs.plugins.kotlin.android) apply false
}

val versionCode = libs.versions.appversioncode.get().toInt()
val versionName = libs.versions.appversion.get()

extra.apply {
    set("versionCode", versionCode)
    set("versionName", versionName)
}

allprojects {
    group = "com.github.yausername"
    version = versionName
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}



