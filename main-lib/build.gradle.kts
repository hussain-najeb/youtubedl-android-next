import com.vanniktech.maven.publish.AndroidSingleVariantLibrary
import com.vanniktech.maven.publish.JavadocJar
import com.vanniktech.maven.publish.SourcesJar

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.maven.publish)
    alias(libs.plugins.ktlint)
}

group = rootProject.group
version = rootProject.version

android {
    namespace = "org.foss.youtube.next"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("proguard-rules.pro")
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

mavenPublishing {
    publishToMavenCentral(automaticRelease = false)
    signAllPublications()

    coordinates(
        groupId = project.group.toString(),
        artifactId = "youtubedl-android-next",
        version = project.version.toString()
    )

    configure(
        AndroidSingleVariantLibrary(
            javadocJar = JavadocJar.Empty(),
            sourcesJar = SourcesJar.Sources(),
            variant = "release"
        )
    )

    pom {
        name.set("youtubedl-android-next")
        description.set("yt-dlp for Android")
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

dependencies {
    implementation(project(":natives"))
    testImplementation(libs.junit)
    androidTestImplementation(libs.android.junit)
    androidTestImplementation(libs.espresso)
    implementation(libs.jackson.databind)
    implementation(libs.jackson.annotations)
    implementation(libs.commons.io)
    implementation(libs.coroutines.core)
    implementation(libs.core.ktx)
    implementation(libs.commons.compress)
}
