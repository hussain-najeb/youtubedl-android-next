plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.maven.publish)
}

group = rootProject.group
version = libs.versions.natives.get()

android {
    namespace = "org.foss.youtube.next.natives"
    compileSdk = 37

         defaultConfig {
             minSdk = 24
         }
}

val onJitPack = System.getenv("JITPACK") == "true"

mavenPublishing {
    if (!onJitPack) {
        publishToMavenCentral(automaticRelease = false)
        signAllPublications()
    }
    coordinates(
        groupId = "io.github.hussain-najeb",
        artifactId = "youtubedl-android-next-natives",
        version = libs.versions.natives.get()
    )

    pom {
        name.set("youtubedl-android-next-natives")
        description.set("Native libraries (FFmpeg, Python, aria2) for youtubedl-android-next")
        url.set("https://github.com/hussain-najeb/youtubedl-android-next")
        inceptionYear.set("2019")
        licenses {
            license {
                name.set("GPL-3.0 license")
                url.set("https://www.gnu.org/licenses/gpl-3.0.en.html")
                distribution.set("repo")
            }
        }
        developers {
            developer {
                id.set("hussain-najeb")
                name.set("Hussain Najeb")
                url.set("https://github.com/hussain-najeb")
            }
        }
        scm {
            url.set("https://github.com/hussain-najeb/youtubedl-android-next")
            connection.set("scm:git:git://github.com/hussain-najeb/youtubedl-android-next.git")
            developerConnection.set("scm:git:ssh://git@github.com/hussain-najeb/youtubedl-android-next.git")
        }
    }
}