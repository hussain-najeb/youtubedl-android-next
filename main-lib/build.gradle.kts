plugins {
    alias(libs.plugins.android.library)
    `maven-publish`
    signing
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

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = project.group.toString()
            artifactId = project.name
            version = project.version.toString()
            afterEvaluate { from(components["release"]) }
            pom {
                name.set("youtubedl-android-next")
                description.set("yt-dlp for Android")
                url.set("https://github.com/hussain-najeb/youtubedl-android")
                inceptionYear.set("2019")
                licenses {
                    license {
                        name.set("GPL-3.0 license")
                        url.set("https://www.gnu.org/licenses/gpl-3.0.en.html")
                    }
                }
                developers {
                    developer {
                        id.set("hussain-najeb")
                        name.set("Hussain Najeb")
                    }
                }
                scm {
                    connection.set("scm:git:https://github.com/hussain-najeb/youtubedl-android")
                    url.set("https://github.com/hussain-najeb/youtubedl-android")
                }
            }
        }
    }
    repositories {
        maven {
            url = rootProject.layout.buildDirectory.dir("staging-deploy").get().asFile.toURI()
        }
    }
}

signing {
    useGpgCmd()
    sign(publishing.publications)
}

dependencies {
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
